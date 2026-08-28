#include <assert.h>
#include <errno.h>
#include <getopt.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "aambundle.h"
#include "aavm.h"

uint8_t *story;
uint32_t storysize;

static char *dirname;
static char *storyfile;

int charset_warning_level = WARN_DEFAULT;
int input_warning_level = WARN_DEFAULT;
int style_warning_level = WARN_DEFAULT;

int nwarning;
static int warnings_as_errors;
static int show_all_help;

static unsigned int warned_mask;

static const struct {
	const char *category;
	int *level;
} warn_info[WARN_COUNT] = {
	{"error",    NULL},
	{"charset",  &charset_warning_level},
	{"input",    &input_warning_level},
	{"style",    &style_warning_level}
};

void vwarning(warn_id_t id, const char *fmt, va_list ap) {
	char msg[1024];

	// Did we turn this warning off?
	if(id < WARN_COUNT && warn_info[id].level && *warn_info[id].level == WARN_NEVER) return;

	vsnprintf(msg, sizeof(msg), fmt, ap);

	fprintf(stderr, "%s %s\n", id==WARN_ERROR || warnings_as_errors ? "Error:" : "Warning:", msg);
	if(id < WARN_COUNT && warn_info[id].level && *warn_info[id].level != WARN_ALWAYS) {
		// Give a hint for the disable warning option the first time.
		if(!(warned_mask & (1u << id))) {
			fprintf(stderr, "(Use --no-warn-%s to disable %s warnings.)\n",
				warn_info[id].category, warn_info[id].category);
			warned_mask |= (1u << id);
		}
	}
	nwarning++;
}

void warning(warn_id_t id, const char *fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	vwarning(id, fmt, ap);
	va_end(ap);
}

static int append_name(char *storyname, int storynamesize, int snamelen, char ch) {
	if(snamelen < storynamesize - 1) {
		if((ch >= 'a' && ch <= 'z')
		|| (ch >= 'A' && ch <= 'Z')
		|| (ch >= '0' && ch <= '9')) {
			storyname[snamelen++] = ch;
		} else {
			storyname[snamelen++] = '-';
		}
	}
	return snamelen;
}

// Stories without a title in their metadata are named after
// the base name of the input file, e.g. "foo/bar.aastory"
// becomes "bar".

static int name_from_filename(char *storyname, int storynamesize) {
	char *base, *end, *p;
	int snamelen = 0;

	if(!storyfile) {
		return 0;
	}
	base = storyfile;
	for(p = storyfile; *p; p++) {
		if(*p == '/' || *p == '\\') {
			base = p + 1;
		}
	}
	end = 0;
	for(p = base; *p; p++) {
		if(*p == '.') {
			end = p;
		}
	}
	if(!end || end == base) {
		end = p;
	}
	for(p = base; p < end; p++) {
		snamelen = append_name(storyname, storynamesize, snamelen, *p);
	}
	storyname[snamelen] = 0;
	return snamelen;
}

void visit_chunks(char *storyname, int storynamesize, chunk_visitor_t chunk_visitor) {
	uint32_t pos = 12, size;
	uint8_t *chunk;
	char head[5], ch;
	int n, i;
	int snamelen = 0;

	while(pos < storysize) {
		chunk = story + pos;
		memcpy(head, chunk, 4);
		head[4] = 0;
		size =
			(chunk[4] << 24) |
			(chunk[5] << 16) |
			(chunk[6] << 8) |
			(chunk[7] << 0);
		chunk += 8;
		if(!strcmp(head, "META")) {
			n = *chunk++;
			for(i = 0; i < n; i++) {
				if(chunk[0] == AAMETA_TITLE) {
					chunk++;
					while((ch = *chunk++)) {
						snamelen = append_name(storyname, storynamesize, snamelen, ch);
					}
					storyname[snamelen] = 0;
				} else {
					while(*chunk++);
				}
			}
		}

		if(chunk_visitor) { // Backend-specific chunk handling
			chunk_visitor(head, dirname, chunk, size);
		}
		pos += (8 + size + 1) & ~1;
	}

	if(!snamelen) {
		snamelen = name_from_filename(storyname, storynamesize);
	}
	if(!snamelen) {
		snprintf(storyname, storynamesize, "story");
	}
}

static uint8_t unicode_buffer[5];
uint8_t *unicode_to_utf8(const uint32_t ch) { // Encodes a single Unicode character to a UTF-8 string for printing
	uint8_t *dest = unicode_buffer;
	if(ch < 0x80) {
		*dest++ = ch;
		*dest = 0;
	} else if(ch < 0x800) {
		*dest++ = 0xc0 |  (ch >>  6); // 11000000
		*dest++ = 0x80 | ((ch >>  0) & 0x3f);
		*dest = 0;
	} else if(ch < 0x10000) {
		*dest++ = 0xe0 |  (ch >> 12); // 11100000
		*dest++ = 0x80 | ((ch >>  6) & 0x3f);
		*dest++ = 0x80 | ((ch >>  0) & 0x3f);
		*dest = 0;
	} else if(ch < 0x110000) {
		*dest++ = 0xf0 |  (ch >> 18); // 11110000
		*dest++ = 0x80 | ((ch >> 12) & 0x3f);
		*dest++ = 0x80 | ((ch >>  6) & 0x3f);
		*dest++ = 0x80 | ((ch >>  0) & 0x3f);
		*dest = 0;
	}
	return unicode_buffer;
}

static char dictionary_word_buffer[256]; // Maximum length of a dictionary word, plus terminator
char* print_n_characters_from(uint8_t *chunk, uint32_t offset, uint8_t number) {
	for(uint8_t i=0; i<number; i++) {
		if(chunk[offset+i] > 0x7f) {
			dictionary_word_buffer[i] = 'X';
		} else {
			dictionary_word_buffer[i] = chunk[offset+i];
		}
	}
	dictionary_word_buffer[number] = 0;
	return dictionary_word_buffer;
}

// This expects to be passed the DICT and LANG chunks
void warn_about_nonascii(uint8_t *dict, uint32_t dictsize, uint8_t *lang, uint32_t langsize) {
	uint16_t nword = (dict[0] << 8) | dict[1];
	uint32_t wordstart; // Offset in chunk
	uint8_t wordlength;
	uint32_t pointer;
	uint32_t exttable = (lang[2] << 8) | lang[3];
	exttable++; // Skip past number of extended characters
	uint32_t unichar;
	uint8_t aachar;

	for(uint16_t i = 0; i < nword; i++) {
		pointer = 2 + 3*i; // 2 bytes for number of words, then each word is 1 byte length, 2 bytes starting position
		wordlength = dict[pointer];
		wordstart = (dict[pointer+1] << 8) | dict[pointer+2];

		for(uint32_t j = wordstart; j < wordstart+wordlength; j++) {
			if(dict[j] > 0x7f) { // Problem!
				// We need to figure out what this character actually *is* to report it
				aachar = dict[j] & 0x7f;
				unichar = (
					(lang[exttable+5*aachar+2] << 16) |
					(lang[exttable+5*aachar+3] << 8) |
					(lang[exttable+5*aachar+4])
				);
				warning(WARN_INPUT, "Extended character %d (%s, U+%04x) found in dictionary word '%s'. This word will not be recognized in user input.",
					dict[j],
					unicode_to_utf8(unichar),
					unichar,
					print_n_characters_from(dict, wordstart, wordlength)
				);
			}
		}
	}
}

static uint32_t chunk_size(const uint8_t *chunk) {
	return
		(chunk[4] << 24) |
		(chunk[5] << 16) |
		(chunk[6] << 8) |
		(chunk[7] << 0);
}

uint8_t *find_chunk(const char *id, uint32_t *sizep) {
	uint32_t pos = 12, size;

	while(pos + 8 <= storysize) {
		size = chunk_size(story + pos);
		if(pos + 8 + size > storysize) break;
		if(!memcmp(story + pos, id, 4)) {
			if(sizep) *sizep = size;
			return story + pos + 8;
		}
		pos += (8 + size + 1) & ~1;
	}

	return 0;
}

// The output buffer that rewrite_chunks() assembles the new story in.
// It replaces the story buffer at the end of the pass, so it grows on demand.

static uint8_t *out;
static uint32_t outsize, outalloc;

static void out_reserve(uint32_t n) {
	if(outsize + n > outalloc) {
		outalloc = 2 * (outsize + n) + 0x1000;
		out = realloc(out, outalloc);
		if(!out) {
			warning(WARN_ERROR, "Out of memory.");
			exit(1);
		}
	}
}

static void emit_chunk(const char *id, const uint8_t *data, uint32_t size) {
	uint32_t total = (8 + size + 1) & ~1;

	out_reserve(total);
	memcpy(out + outsize, id, 4);
	out[outsize + 4] = (size >> 24) & 0xff;
	out[outsize + 5] = (size >> 16) & 0xff;
	out[outsize + 6] = (size >> 8) & 0xff;
	out[outsize + 7] = (size >> 0) & 0xff;
	memcpy(out + outsize + 8, data, size);
	if(total > 8 + size) {
		out[outsize + 8 + size] = 0;
	}
	outsize += total;
}

// The padding is a "    " chunk
static void emit_padding(uint32_t pad) {
	assert(pad >= 8);
	out_reserve(pad);
	memcpy(out + outsize, "    ", 4);
	out[outsize + 4] = 0;
	out[outsize + 5] = 0;
	out[outsize + 6] = ((pad - 8) >> 8) & 0xff;
	out[outsize + 7] = ((pad - 8) >> 0) & 0xff;
	memset(out + outsize + 8, 0, pad - 8);
	outsize += pad;
}


void rewrite_chunks(chunk_rewriter_t rewriter, int align_writ) {
	uint32_t pos = 12, size, newsize;
	uint8_t *chunk, *newdata;
	char head[5], newid[5];
	chunk_action_t action;
	int pad;

	out = 0;
	outalloc = 0;
	outsize = 0;
	out_reserve(12);
	memcpy(out, story, 12);
	outsize = 12;

	while(pos < storysize) {
		chunk = story + pos;
		memcpy(head, chunk, 4);
		head[4] = 0;
		size = chunk_size(chunk);

		memcpy(newid, head, 5);
		newdata = chunk + 8;
		newsize = size;
		action = rewriter
			? rewriter(head, chunk + 8, size, newid, &newdata, &newsize)
			: CHUNK_KEEP;
		if(action == CHUNK_INSERT) {
			// Emit a new chunk before the current one, then keep
			// the current chunk as it is. newid/newdata/newsize
			// hold the inserted chunk; they are copied into the
			// output buffer by emit_chunk() before we fall through.
			emit_chunk(newid, newdata, newsize);
			memcpy(newid, head, 5);
			newdata = chunk + 8;
			newsize = size;
			action = CHUNK_KEEP;
		}
		if(action != CHUNK_REPLACE) {
			memcpy(newid, head, 5);
			newdata = chunk + 8;
			newsize = size;
		}

		if(action != CHUNK_DROP) {
			if(align_writ && !memcmp(newid, "WRIT", 4)) {
				// The 6502 engine expects the WRIT chunk to be page-aligned
				pad = 0x100 - (outsize & 0xff);
				assert(!(pad & 1));

				// Only align if we can write at least 8 bytes
				if(pad < 0xf0) {
					if(pad < 8) pad += 0x100;
					emit_padding(pad);
				}
			}
			emit_chunk(newid, newdata, newsize);
		}

		pos += (8 + size + 1) & ~1;
	}

	free(story);
	story = out;
	storysize = outsize;
	out = 0;
	outalloc = 0;
	outsize = 0;

	story[4] = ((storysize - 8) >> 24) & 0xff;
	story[5] = ((storysize - 8) >> 16) & 0xff;
	story[6] = ((storysize - 8) >> 8) & 0xff;
	story[7] = ((storysize - 8) >> 0) & 0xff;
}

/* Writes data, then pads the file with zeros up to a multiple of padto
 * bytes (padto = 1 means no padding). dirname may be NULL, in which
 * case name is taken as-is relative to the current directory. */
void writefile_padded(char *dirname, char *name, const uint8_t *data, size_t size, size_t padto) {
	char *filename;
	FILE *f;
	size_t npad;

	if(dirname) {
		filename = malloc(strlen(dirname) + strlen(name) + 2);
		sprintf(filename, "%s/%s", dirname, name);
	} else {
		filename = malloc(strlen(name) + 1);
		strcpy(filename, name);
	}

	f = fopen(filename, "wb");
	if(!f) {
		fprintf(stderr, "%s: %s\n", filename, strerror(errno));
		exit(1);
	}
	if(size != fwrite(data, 1, size, f)) {
		fprintf(stderr, "%s: %s\n", filename, strerror(errno));
		exit(1);
	}
	npad = (padto - size % padto) % padto;
	while(npad--) {
		if(EOF == fputc(0, f)) {
			fprintf(stderr, "%s: %s\n", filename, strerror(errno));
			exit(1);
		}
		size++;
	}
	fclose(f);

	printf("%-14s %7lu bytes\n", name, (unsigned long) size);

	free(filename);
}

void writefile(char *dirname, char *name, const uint8_t *data, size_t size) {
	writefile_padded(dirname, name, data, size, 1);
}

void usage(char *prgname, int all) {
	fprintf(stderr, "Aa-machine tools " VERSION "\n");
	fprintf(stderr, "Copyright 2019-2026 Linus Akesson and the Dialog Project contributors.\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "Usage: %s [options] filename.aastory\n", prgname);
	fprintf(stderr, "\n");
	fprintf(stderr, "Options:\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "--version   -V    Display the program version.\n");
	fprintf(stderr, "--help      -h    Display this information.\n");
	fprintf(stderr, "--help-all        Display all options, including warnings.\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "--output    -o    Set output directory/file name.\n");
	fprintf(stderr, "--target    -t    Select target (web, c64, apple2, web:story).\n");
	if(all) {
		fprintf(stderr, "\n");
		fprintf(stderr, "Warning options:\n");
		fprintf(stderr, "--warn-charset          Always warn about codepoints the target cannot render.\n");
		fprintf(stderr, "--no-warn-charset       Never warn about codepoints the target cannot render.\n");
		fprintf(stderr, "--warn-input            Always warn about words the target cannot type.\n");
		fprintf(stderr, "--no-warn-input         Never warn about words the target cannot type.\n");
		fprintf(stderr, "--warn-style            Always warn about styles the target cannot support.\n");
		fprintf(stderr, "--no-warn-style         Never warn about styles the target cannot support.\n");
		fprintf(stderr, "--warnings-as-errors    Exit with a failure status if anything warned.\n");
	}
	fprintf(stderr, "\n");
	fprintf(stderr, "Targets:\n");
	fprintf(stderr, "web (default)     Directory with web interpreter.\n");
	fprintf(stderr, "c64               Directory with c64 disk image.\n");
	fprintf(stderr, "apple2            Directory with apple2 disk images.\n");
	fprintf(stderr, "web:story         Just story.js for the web interpreter.\n");
	if(all) {
		fprintf(stderr, "aambox            Rewrite to .ustory format for the aambox test platform.\n");
	}
	exit(1);
}

int main(int argc, char **argv) {
	struct option longopts[] = {
		{"help", 0, 0, 'h'},
		{"help-all", 0, &show_all_help, 1},
		{"version", 0, 0, 'V'},
		{"output", 1, 0, 'o'},
		{"target", 1, 0, 't'},
		{"warn-charset", 0, &charset_warning_level, WARN_ALWAYS},
		{"no-warn-charset", 0, &charset_warning_level, WARN_NEVER},
		{"warn-input", 0, &input_warning_level, WARN_ALWAYS},
		{"no-warn-input", 0, &input_warning_level, WARN_NEVER},
		{"warn-style", 0, &style_warning_level, WARN_ALWAYS},
		{"no-warn-style", 0, &style_warning_level, WARN_NEVER},
		{"warnings-as-errors", 0, &warnings_as_errors, 1},
		{0, 0, 0, 0}
	};
	char *prgname = argv[0];
	char *target = "web";
	int opt, i;
	FILE *f;
	uint8_t buf[12];

	do {
		opt = getopt_long(argc, argv, "?hVo:t:", longopts, 0);
		switch(opt) {
			case 0:
				// A long-only option stored its value through
				// the longopts table; nothing more to do.
				break;
			case '?':
			case 'h':
				usage(prgname, show_all_help);
				break;
			case 'V':
				fprintf(stderr, "Aa-machine tools " VERSION "\n");
				exit(0);
			case 'o':
				dirname = strdup(optarg);
				break;
			case 't':
				target = strdup(optarg);
				break;
			default:
				if(opt >= 0) {
					warning(WARN_ERROR, "Unimplemented option '%c'", opt);
					exit(1);
				}
				break;
		}
	} while(opt >= 0);

	if(optind >= argc) {
		usage(prgname, show_all_help);
	}

	storyfile = argv[optind];

	if(strcmp(target, "web")
	&& strcmp(target, "web:story")
	&& strcmp(target, "c64")
	&& strcmp(target, "apple2")
	&& strcmp(target, "aambox")) {
		warning(WARN_ERROR, "Unsupported target \"%s\".", target);
		exit(1);
	}

	if(!dirname) {
		if(!strcmp(target, "web:story")) {
			dirname = "story.js";
		} else if(!strcmp(target, "aambox")) {
			dirname = "story.ustory";
		} else {
			dirname = malloc(strlen(argv[optind]) + 8);
			strcpy(dirname, argv[optind]);
			for(i = strlen(dirname) - 1; i >= 0; i--) {
				if(dirname[i] == '.') {
					break;
				}
				if(dirname[i] == '/' || dirname[i] == '\\') {
					i = -1;
					break;
				}
			}
			if(i < 0) {
				i = strlen(dirname);
			}
			dirname[i] = 0;
		}
	}

	f = fopen(argv[optind], "rb");
	if(!f) {
		warning(WARN_ERROR, "%s: %s", argv[optind], strerror(errno));
		exit(1);
	}
	if(12 != fread(buf, 1, 12, f)
	|| memcmp(buf, "FORM", 4)
	|| memcmp(buf + 8, "AAVM", 4)) {
		warning(WARN_ERROR, "Bad or missing file header.");
		exit(1);
	}
	storysize = 8 +
		((buf[4] << 24) |
		(buf[5] << 16) |
		(buf[6] << 8) |
		(buf[7] << 0));
	fseek(f, 0, SEEK_SET);

	story = malloc(storysize + 0x108);
	if(storysize != fread(story, 1, storysize, f)) {
		warning(WARN_ERROR, "Failed to read all of '%s': %s", argv[optind], strerror(errno));
		exit(1);
	}

	fclose(f);

	if(story[20] > VER_MAJOR || (story[20] == VER_MAJOR && story[21] > VER_MINOR)) {
		warning(WARN_ERROR, "Unsupported story file version: %d.%d is more than %d.%d", story[20], story[21], VER_MAJOR, VER_MINOR);
		exit(1);
	}

	if(!strcmp(target, "web:story")) {
		bundle_web_story(dirname);
	} else if(!strcmp(target, "aambox")) {
		bundle_aambox(dirname);
	} else {
		if(mkdir(dirname, 0777) && errno != EEXIST) {
			warning(WARN_ERROR, "%s: %s", dirname, strerror(errno));
			exit(1);
		}
		if(!strcmp(target, "web")) {
			bundle_web(dirname);
		} else if(!strcmp(target, "c64")) {
			bundle_c64(dirname);
		} else if(!strcmp(target, "apple2")) {
			bundle_apple2(dirname);
		}
	}

	return (warnings_as_errors && nwarning)? 1 : 0;
}
