#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "aambundle.h"
#include "aavm.h"

// ============================================================================
// USTY chunk generation: precomputed style table for the 6502 engines.
//
// Parses the LOOK chunk (CSS declarations) once, in C, and emits the compact
// binary table defined in aamshow.c. USTY replaces LOOK on the 6502
// targets which have no style sheet parser.
//
// The parser mirrors both the dialog compiler's effective CSS subset
// (~/if/dialog/src/frontend.c:2899-3000): case-insensitive keys,
// unknown properties ignored, width/height accept % (relative)
// and em/ch/en (absolute), margins absolute only, fractional units truncated.
// ============================================================================

// The high nibble of the tag byte names the target, the low nibble the
// format revision (0..15, internal only so it can recycle)
#define STY_TAG_AAMBOX  0x00
#define STY_TAG_C64     0x10
#define STY_TAG_APPLE2  0x20

#define STY_RELW  0x01
#define STY_RELH  0x02

#define NOCOLOR   0x80    // "$80 = not set" sentinel for the sty fg field

struct sty_target {
	const char *name;
	uint8_t tag;
	int have_vic_color;     // per-character fg color (c64)
	uint8_t stymask;        // AASTYLE_* bits the frontend can actually act on
	int mincols, maxcols;	// 40 for c64, 40-80 for apple2, 80 for aambox
	int maxrows;		// 20 for all
};

static const struct sty_target sty_aambox = {
	"aambox", STY_TAG_AAMBOX, 0,
	0,
	80, 80, 20
};
static const struct sty_target sty_c64 = {
	"c64", STY_TAG_C64, 1,
	AASTYLE_REVERSE | AASTYLE_BOLD | AASTYLE_ITALIC,
	40, 40, 20
};
static const struct sty_target sty_apple2 = {
	"apple2", STY_TAG_APPLE2, 0,
	AASTYLE_REVERSE,
	40, 80, 20
};

static const struct sty_target *sty_target;
static uint8_t *sty_payload;    // malloc'd USTY chunk payload (leaked, tool lifetime)
static uint32_t sty_size;
static int sty_emitted;

// Per-class record, one for every class in LOOK.
typedef struct {
	uint8_t styon, styoff;  // AASTYLE_* bits
	uint8_t fg;             // c64 palette index, NOCOLOR = inherit
	uint8_t mtop, mbottom;  // top/bottom margins in rows
	uint8_t width, height;  // width/height in columns
	uint8_t flo;            // 0 none, 1 left, 2 right
	uint8_t flags;          // STY_RELW | STY_RELH
} styclass;

// ----------------------------------------------------------------------------
// Color mapping. The C64 has a 16-color palette; web colors are reduced to
// the nearest VIC-II color by RGB distance. "inherit", "initial" and
// "transparent" (or alpha 0) leave the field unset.

static const uint8_t c64_rgb[16][3] = {
	{0, 0, 0}, {255, 255, 255}, {136, 0, 0}, {170, 255, 238},
	{204, 68, 204}, {0, 204, 85}, {0, 0, 170}, {238, 238, 119},
	{221, 136, 85}, {102, 68, 0}, {255, 119, 119}, {51, 51, 51},
	{119, 119, 119}, {170, 255, 102}, {0, 136, 255}, {187, 187, 187}
};

// CSS color names map by name to their obvious VIC-II counterparts
static const struct {
	const char *name;
	uint8_t vic;
} css2vic[] = {
	// canonical names (0..15 in order)
	{"black", 0},
	{"white", 1},
	{"red", 2},
	{"cyan", 3},
	{"purple", 4},
	{"green", 5},
	{"blue", 6},
	{"yellow", 7},
	{"orange", 8},
	{"brown", 9},
	{"pink", 10},
	{"darkgrey", 11},
	{"mediumgrey", 12},
	{"lightgreen", 13},
	{"lightblue", 14},
	{"lightgrey", 15},
	// synonyms
	{"maroon", 2},
	{"aqua", 3},
	{"teal", 3},
	{"magenta", 4},
	{"fuchsia", 4},
	{"lime", 5},
	{"navy", 6},
	{"lightred", 10},
	{"gray", 11},
	{"grey", 11},
	{"darkgray", 11},
	{"lightgray", 15},
	{"silver", 15},
};

// Style warnings, routed through swarn() so that they can be silenced
// while parsing declarations that a -iftf-sys- declaration in the same
// class overrides anyway. They are prefixed with the style-name of the
// class being parsed (see sty_name), so the author can tell which
// declaration each complaint is about.
static int sty_quiet;

// Name of the style class currently being parsed; "class N" if the LOOK
// chunk does not carry a style-name: declaration for it.
static const char *sty_name = 0;

static void swarn(const char *fmt, ...) {
	va_list ap;
	char msg[1024];
	if(sty_quiet) return;
	va_start(ap, fmt);
	vsnprintf(msg, sizeof(msg), fmt, ap);
	va_end(ap);
	warning(WARN_STYLE, "style class %s: %s", sty_name ? sty_name : "(unknown)", msg);
}

// Map an rgb triplet to the nearest VIC-II color, using a perceptual
// distance (weighted RGB, a standard cheap approximation of CIE lightness).
static int rgb_to_c64(int r, int g, int b) {
	int best = 0, bestdist = 0x7fffffff;
	int i;

	for(i = 0; i < 16; i++) {
		long dr = r - c64_rgb[i][0];
		long dg = g - c64_rgb[i][1];
		long db = b - c64_rgb[i][2];
		long dist = 2 * dr * dr + 4 * dg * dg + 3 * db * db;
		if(dist < bestdist) {
			bestdist = dist;
			best = i;
		}
	}
	if(bestdist > (2+3+4)*64*64) {
		swarn("The color #%02x%02x%02x is not accurately represented on %s, the closest is %s (index %d, #%02x%02x%02x).",
			r, g, b, sty_target->name, css2vic[best].name, best,
			c64_rgb[best][0], c64_rgb[best][1], c64_rgb[best][2]);
	}
	return best;
}

// Hex digit to value.
static int hex(char c) {
	return c >= '0' && c <= '9'? c - '0' : (c | 0x20) - 'a' + 10;
}

// Parse "  #rgb", "#rrggbb", "rgb(r,g,b)", "rgba(r,g,b,a)", a name,
//   or a specific VIC-II color index (0..15).
// Returns 1 and sets *out to a palette index;
// returns 0 if the value is not a usable color
//   (inherit, initial, transparent, alpha 0, garbage).
static int parse_color(const char *v, int *out) {
	int i, r = 0, g = 0, b = 0, alpha = 255, n;

	while(*v == ' ' || *v == '\t') v++;

	if(!strncmp(v, "inherit", 7)
	|| !strncmp(v, "initial", 7)
	|| !strncmp(v, "transparent", 11)) {
		return 0;
	}

	if(v[0] == '#') {
		v++;
		n = 0;
		while(v[n] && ((v[n] >= '0' && v[n] <= '9') || (v[n] >= 'a' && v[n] <= 'f') || (v[n] >= 'A' && v[n] <= 'F'))) {
			n++;
		}
		if(n == 3) {
			r = hex(v[0]) * 0x11;
			g = hex(v[1]) * 0x11;
			b = hex(v[2]) * 0x11;
		}else if(n == 6) {
			r = (hex(v[0]) << 4) | hex(v[1]);
			g = (hex(v[2]) << 4) | hex(v[3]);
			b = (hex(v[4]) << 4) | hex(v[5]);
		} else {
			return 0;
		}
	} else if(!strncmp(v, "rgb", 3)) {
		float af;
		v += 3;
		if(*v == 'a') v++;
		if(*v != '(') return 0;
		v++;
		if(sscanf(v, "%d , %d , %d , %f", &r, &g, &b, &af) == 4) {
			// rgba: alpha is a 0..1 float
			alpha = (int)(af * 255 + 0.5);
			alpha = alpha < 0? 0 : alpha > 255? 255 : alpha;
			if(alpha == 0) return 0;
		} else {
			if(sscanf(v, "%d , %d , %d", &r, &g, &b) != 3) return 0;
		}
	} else if(*v >= '0' && *v <= '9') {
		// Naked VIC color index: 0..15 selects the palette entry itself,
		// so 3 is cyan no matter what hue CSS would call it. Reject
		// trailing junk so "10px" and friends don't quietly become 10.
		const char* v_old = v;
		n = atoi(v);
		while(*v >= '0' && *v <= '9') v++;
		while(*v == ' ' || *v == '\t') v++;
		if(!*v && n <= 15) {
			*out = n;
			return 1;
		}
		swarn("Invalid VIC color index \"%s\", must be in range 0..15.", v_old);
		return 0;
	} else {
		int vic = -1;
		for(i = 0; i < (int)(sizeof(css2vic) / sizeof(css2vic[0])); i++) {
			if(!strcasecmp(v, css2vic[i].name)) {
				vic = css2vic[i].vic;
				break;
			}
		}
		if(vic < 0) {
			swarn("Unknown c64 color \"%s\".", v);
			return 0;
		}
		*out = vic;
		return 1;
	}

	// Hex and rgb() paths land here with r/g/b filled in.
	*out = rgb_to_c64(r, g, b);
	return 1;
}

// ----------------------------------------------------------------------------
// CSS value parsing.
// Returns the number of conversions:
//   0 = not a length
//   1 = bare number,
//   2 = number and unit
//       (*unit is "" for a bare number, "%" or "em"/"ch"/"en")
static int scan_length(const char *value, int *val, char *unit) {
	float f;
	int n;

	while(*value == ' ' || *value == '\t') value++;
	if((*value < '0' || *value > '9') && *value != '.') return 0;
	unit[0] = 0;
	n = sscanf(value, "%f %15s", &f, unit);
	if(n < 1) return 0;
	*val = (int) f;         // fractions are truncated
	return n;
}

static int isabsunit(const char *unit) {
	return !strcmp(unit, "em") || !strcmp(unit, "ch") || !strcmp(unit, "en");
}

// Parse one null-terminated declaration, e.g. "width: 100%" or
// "-iftf-sys-c64-color: red". The line is copied so the key can be lowercased
// in place; 'key' starts at the buffer, 'value' points into it.
//
// Declarations are parsed in two passes per class (see parse_look):
// - pass 0 takes the unprefixed ones
// - pass 1 the -iftf- ones so they override
static void parse_decl(styclass *c, const char *p, int len, int pass) {
	char buf[256];
	char *colon, *key, *value, *bang, *q;
	int prefixed = 0;
	int matched = 0;

	if(len >= (int) sizeof(buf)) len = sizeof(buf) - 1;
	memcpy(buf, p, len);
	buf[len] = 0;

	colon = strchr(buf, ':');
	if(!colon) return;
	*colon = 0;
	value = colon + 1;
	while(*value == ' ' || *value == '\t') value++;
	bang = strchr(value, '!');     // strip "!important"
	if(bang) *bang = 0;
	while(*value == ' ' || *value == '\t') value++;

	key = buf;
	while(*key == ' ' || *key == '\t') key++;
	for(q = key; *q; q++) {
		if(*q >= 'A' && *q <= 'Z') *q |= 0x20; // make lowercase
	}
	while(q > key && (q[-1] == ' ' || q[-1] == '\t')) *--q = 0;

	// -iftf-sys-<target>-* properties
	if(!strncmp(key, "-iftf-sys-", 10)) {
		prefixed = 1;
		char *prop;
		key += 10;
		prop = strchr(key, '-');
		if(!prop) return;
		*prop = 0;
		// ignore if not the target system
		if(strcmp(key, sty_target->name)) {
			return;
		}
		key = prop + 1;
	}
	if(prefixed != pass) return;

	char param[32] = { 0 };
	sscanf(value, "%31s", param);

	if(!strcmp(key, "-iftf-text-decoration")) {
		if(!strcmp(param, "reverse")) c->styon |= AASTYLE_REVERSE;
		else if(!strcmp(param, "none")) c->styoff |= AASTYLE_REVERSE;
		else swarn("Invalid value for %s: %s", key, value);
		return;
	}

	if(!strcmp(key, "width") || !strcmp(key, "height")) {
		int v;
		char unit[16];
		int n = scan_length(value, &v, unit);
		matched = 1;
		if(n == 2 && !strcmp(unit, "%")) {
			if(v > 100) {
				swarn("Percent %s \"%s\" is more than 100%% and will not fit the screen.",
					key, value);
			}
			if(*key == 'w') {
				c->width = v;
				c->flags |= STY_RELW;
			} else {
				c->height = v;
				c->flags |= STY_RELH;
			}
		} else if(n >= 1 && (!unit[0] || isabsunit(unit))) {
			// Bare number or em/ch/en: absolute.
			if(*key == 'w') c->width = v;
			else c->height = v;
		} else {
			swarn("Ignoring %s: unsupported value \"%s\".", key, value);
		}
	} else if(!strcmp(key, "margin-top") || !strcmp(key, "margin-bottom")) {
		int v;
		char unit[16];
		int n = scan_length(value, &v, unit);
		matched = 1;
		if(n >= 1 && (!unit[0] || isabsunit(unit))) {
			// Absolute only
			if(!strcmp(key, "margin-top")) c->mtop = v;
			else if(!strcmp(key, "margin-bottom")) c->mbottom = v;
		} else if(n == 2 && !strcmp(unit, "%")) {
			swarn("Percent %s \"%s\" is not supported and was ignored.", key, value);
		} else {
			swarn("Ignoring %s: unsupported value \"%s\".", key, value);
		}
	} else if(!strcmp(key, "float")) {
		matched = 1;
		if(!strcmp(param, "left")) c->flo = 1;
		else if(!strcmp(param, "right")) c->flo = 2;
		else if(strcmp(param, "none") && strcmp(param, "inherit")) {
			swarn("Invalid value for float: %s (only left, right and none are supported).", value);
		}
	} else if(!strcmp(key, "margin")) {
		matched = 1;
		if(!strcmp(param, "auto")) c->flo = 3;
		else swarn("Invalid value for margin: %s (use \"margin: auto\").", value);
	} else if(!strcmp(key, "font-style")) {
		matched = 1;
		if(!strcmp(param, "italic") || !strcmp(param, "oblique"))
			c->styon |= AASTYLE_ITALIC;
		else if(!strcmp(param, "normal")) c->styoff |= AASTYLE_ITALIC;
		else if(strcmp(param, "inherit")) {
			swarn("Invalid value for font-style: %s (only italic, oblique and normal are supported).", value);
		}
	} else if(!strcmp(key, "font-weight")) {
		matched = 1;
		if(!strcmp(param, "bold")) c->styon |= AASTYLE_BOLD;
		else if(!strcmp(param, "normal")) c->styoff |= AASTYLE_BOLD;
		else if(strcmp(param, "inherit")) {
			// In particular: numeric weights (400, 700) are valid web
			// CSS but mean nothing here.
			swarn("Invalid value for font-weight: %s (only bold and normal are supported).", value);
		}
	} else if(!strcmp(key, "font-family")) {
		matched = 1;
		if(strstr(value, "monospace")) c->styon |= AASTYLE_FIXED;
		else if(strcmp(param, "inherit")) c->styoff |= AASTYLE_FIXED;
	} else if(!strcmp(key, "text-decoration") || !strcmp(key, "reverse-video")) {
		matched = 1;
		if(strstr(value, "reverse")) {
			c->styon |= AASTYLE_REVERSE;
		} else if(strcmp(param, "inherit")) {
			c->styoff |= AASTYLE_REVERSE;
			if(!strcmp(key, "text-decoration") && strcmp(param, "none")) {
				swarn("Invalid value for text-decoration: %s (only reverse, none and inherit are supported).", value);
			}
		}
	} else if(!strcmp(key, "color")) {
		matched = 1;
		if(sty_target->have_vic_color) {
			int ci;
			if(parse_color(value, &ci)) {
				c->fg = ci;
			}
		} else {
			swarn("color is not supported on %s and was ignored.", sty_target->name);
		}
	} else if(!strcmp(key, "display")) {
		matched = 1;
		if(!strcmp(param, "none")) {
			swarn("display: none is not supported; the element will still be shown.");
		}
	} else if(!strcmp(key, "visibility")) {
		matched = 1;
		if(!strcmp(param, "hidden")) {
			swarn("visibility: hidden is not supported; the element will still be shown.");
		}
	}

	// A prefix that named the target but a property the bundler does not know.
	if(prefixed && !matched) {
		swarn("-iftf-sys-%s-%s is not supported yet.", sty_target->name, key);
	}
	// Anything else is ignored, as an interpreter must per the spec.
}

static void make_flat(uint8_t *r, const styclass *c) {
	uint8_t flags = c->flags & (USTY_FL_RELW | USTY_FL_RELH);

	if(c->flo == 1) flags |= USTY_FL_FLOATL;
	else if(c->flo == 2) flags |= USTY_FL_FLOATR;

	r[USTY_F_WIDTH] = c->width;
	r[USTY_F_HEIGHT] = c->height;
	r[USTY_F_MTOP] = c->mtop;
	r[USTY_F_MBOTTOM] = c->mbottom;
	r[USTY_F_STYON] = c->styon & sty_target->stymask;
	r[USTY_F_STYOFF] = c->styoff & sty_target->stymask;
	r[USTY_F_FLAGS] = flags;
	r[USTY_F_FG] = c->fg;
}

static uint16_t get16(const uint8_t *p) {
	return (p[0] << 8) | p[1];
}

// Length of the null-terminated line at look[p], clamped to end.
static uint32_t line_len(const uint8_t *look, uint32_t p, uint32_t end) {
	uint32_t len = 0;
	while(p + len < end && look[p + len]) len++;
	return len;
}

// ----------------------------------------------------------------------------
// LOOK parse: read the class count, then walk each class's declaration
// block (null-terminated strings, a lone null byte ends the block)

static styclass *parse_look(int *nclassp) {
	uint8_t *look;
	uint32_t looksize;
	uint16_t n;
	styclass *cls;
	int i;
	int pass;

	look = find_chunk("LOOK", &looksize);
	if(!look) return 0;

	n = get16(look);
	if(n > 255) {
		warning(WARN_STYLE, "Story has %d style classes, more than a USTY table can index (255).", n);
		return 0;
	}
	// need at least one style, ok if it's empty
	if (!n) n++;
	cls = calloc(n, sizeof(styclass));
	if(!cls) return 0;

	// fg defaults to "not set", which is not the same as black.
	for(i = 0; i < n; i++) {
		cls[i].fg = NOCOLOR;
	}

	for(i = 0; i < n; i++) {
		uint32_t ptr, end, p;
		int hasiftf = 0;
		char pfx[32];
		char namebuf[64];
		size_t plen;

		if((uint32_t)(2 + 2 * i + 2) > looksize) break;
		ptr = get16(look + 2 + 2 * i);
		if(ptr >= looksize) continue;
		end = looksize;

		// One lookahead pass over the class's declaration lines: pick up
		// its style-name (so warnings can name it), and check whether it
		// carries -iftf-sys-<target>- declarations for this machine. If so,
		// the generic (unprefixed) declarations are only a fallback that the
		// prefixed pass replaces wholesale -- so pass 0 below runs with
		// warnings off, and the author is not scolded twice for the same
		// styling.
		snprintf(namebuf, sizeof(namebuf), "class %d", i);
		sty_name = namebuf; // this is on the stack so we have to unset it
		snprintf(pfx, sizeof(pfx), "-iftf-sys-%s-", sty_target->name);
		plen = strlen(pfx);
		p = ptr;
		while(p < end && look[p]) {
			uint32_t linelen = line_len(look, p, end);
			char line[64], nm[56];

			if(linelen > plen && !strncasecmp((const char *) look + p, pfx, plen))
				hasiftf = 1;
			// "style-name: title", always written in this exact case.
			if(linelen < sizeof(line)) {
				memcpy(line, look + p, linelen);
				line[linelen] = 0;
				if(1 == sscanf(line, " style-name : %55s", nm)) {
					snprintf(namebuf, sizeof(namebuf), "@%s", nm);
					sty_name = namebuf;
				}
			}
			p += linelen + 1;
		}

		// Two passes over the same block: unprefixed declarations first,
		// then the -iftf-sys- ones, so that a prefixed declaration overrides
		// its unprefixed counterpart no matter which comes last in the CSS.
		for(pass = 0; pass < 2; pass++) {
			sty_quiet = hasiftf && pass == 0;
			p = ptr;
			while(p < end && look[p]) {
				uint32_t linelen = line_len(look, p, end);
				parse_decl(&cls[i], (const char *) look + p, linelen, pass);
				p += linelen + 1;
			}
		}
		sty_quiet = 0; // re-enable warnings
		sty_name = 0; // unset style class name
	}
	*nclassp = n;
	return cls;
}

// Build the USTY chunk (revision 13).
//
// The body array is a list of (index, datalen, data...) records, ended by
// a single $ff index byte; datalen is the per-target payload size. The
// payload is padded to an even length after the header so that
// totalwords * 2 is exactly the number of bytes the engine reads.

static uint8_t *build_usty_flat(uint32_t *sizep) {
	styclass *cls;
	int nclass;
	uint8_t *out;
	uint32_t size, recoffs, xstyoffs, blockbytes, totalwords;
	int nxsty = 0, nover = 0, maxnsty, reclen;
	int i;

	cls = parse_look(&nclass);
	if(!cls) return 0;

	recoffs = USTY_HDRSIZE;
	xstyoffs = recoffs + nclass * USTY_RECSIZE;
	reclen = 2;
	maxnsty = 0;

	// Upper bound: the full body array with its terminator, which is what
	// the engine's one-page scan can reach.
	size = xstyoffs + 1;

	out = calloc(1, size);
	if(!out) {
		warning(WARN_ERROR, "Out of memory");
		exit(1);
	}

	out[0] = sty_target->tag | USTY_VERSION;
	out[1] = nclass;
	// out[2] = nxsty, filled in below.
	// out[3] stays 0: reserved (revision 12's xstysize stride byte).
	out[6] = (xstyoffs - recoffs) >> 8;     // from the record base, which is
	out[7] = (xstyoffs - recoffs) & 0xff;   // the pointer the engine holds

	for(i = 0; i < nclass; i++) {
		make_flat(out + recoffs + i * USTY_RECSIZE, &cls[i]);
	}

	// The array always ends in $ff, even empty: the terminator is the only
	// thing that tells the engine's scan to stop.
	out[xstyoffs + nxsty * reclen] = 0xff;

	if(nover) {
		warning(WARN_STYLE, "Too many classes have -iftf-sys-%s- colors (max is %d) so some body styles were dropped.",
			sty_target->name, maxnsty);
	}

	blockbytes = nclass * USTY_RECSIZE + nxsty * reclen + 1;
	totalwords = (blockbytes + 1) / 2; // word = 2 bytes
	size = recoffs + totalwords * 2; // size is in bytes
	out[2] = nxsty;
	out[4] = totalwords >> 8;
	out[5] = totalwords & 0xff;

	free(cls);
	*sizep = size;
	return out;
}

// ----------------------------------------------------------------------------
// Public API.

// Called after rewriting USTY, exits program with an error code it didn't happen.
void gen_usty_check(void) {
	if(sty_target && !sty_emitted) {
		warning(WARN_ERROR,
			"Could not build the %s style table.",
			sty_target->name);
		exit(1);
	}
}

void gen_usty_set_target(const char *target) {
	sty_target = 0;
	if(!strcmp(target, "c64")) {
		sty_target = &sty_c64;
	} else if(!strcmp(target, "apple2")) {
		sty_target = &sty_apple2;
	} else if(!strcmp(target, "aambox")) {
		sty_target = &sty_aambox;
	}
	sty_payload = 0;
	sty_size = 0;
	sty_emitted = 0;
}

chunk_action_t rewrite_6502_sty(
	const char *id,
	uint8_t *data,
	uint32_t size,
	char *newid,
	uint8_t **newdata,
	uint32_t *newsize)
{
	// drop FILE chunks
	if(!strcmp(id, "FILE")) return CHUNK_DROP;

	chunk_action_t act = CHUNK_KEEP;

	if(sty_target && !sty_emitted && !strcmp(id, "LOOK")) {
		if(!sty_payload) {
			sty_payload = build_usty_flat(&sty_size);
		}
		if(sty_payload) {
			memcpy(newid, "USTY", 4);
			*newdata = sty_payload;
			*newsize = sty_size;
			sty_emitted = 1;
			return CHUNK_REPLACE;
		}
	}
	return act;
}