#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct entry {
	uint32_t	glyph;
	int		nrow;	// 0 = no glyph, 8 = glyph
	uint8_t		row[8];
	char		translit[3];
};

struct entry *entries;
int nentry, nalloc;

uint8_t basefont[128][8];

// translit in a2_frontend.s scans the low block with ldx #TRLOW-1 / dex / bpl,
// so an index of $80 or more reads as negative and the scan stops after one
// comparison.

#define MAXTRANS 128

int cmp_entry(const void *a, const void *b) {
	const struct entry *aa = a;
	const struct entry *bb = b;

	return aa->glyph - bb->glyph;
}

struct entry *add(uint32_t glyph) {
	if(nentry == nalloc) {
		nalloc = 2 * nalloc + 8;
		entries = realloc(entries, nalloc * sizeof(struct entry));
		memset(entries + nentry, 0, (nalloc - nentry) * sizeof(struct entry));
	}

	memset(&entries[nentry], 0, sizeof(struct entry));
	entries[nentry].glyph = glyph;
	return &entries[nentry++];
}

struct entry *find(uint32_t glyph) {
	int i;

	for(i = 0; i < nentry; i++) {
		if(entries[i].glyph == glyph) {
			return &entries[i];
		}
	}

	return 0;
}

// Parse the optional transliteration that follows a codepoint, e.g.
//
//	+00c6 "AE"
//
// into e->translit. At most two characters fit the 6502 table.

void parse_translit(struct entry *e, const char *s) {
	int n = 0;

	while(*s == '+' || isxdigit((uint8_t) *s)) s++;
	while(*s == ' ' || *s == '\t') s++;
	if(*s == ';') {		// annotation comment, e.g. `; é LATIN SMALL LETTER E WITH ACUTE`
		return;
	}
	if(*s != '"') {
		if(*s && *s != '\n' && *s != '\r') {
			fprintf(stderr, "U+%04X: expected a quoted transliteration\n", e->glyph);
			exit(1);
		}
		return;
	}
	s++;

	while(*s && *s != '"') {
		int c = (uint8_t) *s++;

		if(c == '\\') {
			switch(*s) {
			case 'x':
				if(1 != sscanf(s + 1, "%2x", &c)) {
					fprintf(stderr, "U+%04X: bad \\x escape\n", e->glyph);
					exit(1);
				}
				s += 3;
				break;
			case 0:
				fprintf(stderr, "U+%04X: trailing backslash\n", e->glyph);
				exit(1);
			default:
				c = (uint8_t) *s++;
				break;
			}
		}

		if(n >= 2) {
			fprintf(stderr, "U+%04X: transliteration is longer than two characters\n", e->glyph);
			exit(1);
		}
		e->translit[n++] = c;
	}

	if(!n) {
		fprintf(stderr, "U+%04X: empty transliteration\n", e->glyph);
		exit(1);
	}
}

// Render one byte of a trc0/trc1 table the way the table was written by hand:
// printable characters as literals, everything else in hex, absent as 0.

void put_char_byte(FILE *f, uint8_t c) {
	if(!c) {
		fprintf(f, "0");
	} else if(isprint(c) && c != '\'' && c != '"' && c != '\\') {
		fprintf(f, "'%c'", c);
	} else {
		fprintf(f, "$%02x", c);
	}
}

void put_table(FILE *f, const char *label, struct entry **tr, int from, int ntr, int which) {
	int i, n = 0;

	fprintf(f, "%s\n", label);
	for(i = from; i < ntr; i++, n++) {
		fprintf(f, "%s", (n & 7)? "," : "\t.byt\t");
		switch(which) {
		case 0: fprintf(f, "$%02x", (tr[i]->glyph >> 8) & 0xff); break;
		case 1: fprintf(f, "$%02x", (tr[i]->glyph >> 0) & 0xff); break;
		case 2: put_char_byte(f, tr[i]->translit[0]); break;
		}
		if((n & 7) == 7) fprintf(f, "\n");
	}
	if(n & 7) fprintf(f, "\n");
}

// Emit the sparse (index, second character) list.

void put_pairs(FILE *f, struct entry **tr, int *p2, int np2) {
	int i;

	fprintf(f, "\nNTR2\t=\t%d\n\n", np2? np2 : 1);

	fprintf(f, "tr2idx\n");
	if(!np2) fprintf(f, "\t.byt\t255\t; never matches\n");
	for(i = 0; i < np2; i++) {
		fprintf(f, "%s%d", (i & 7)? "," : "\t.byt\t", p2[i]);
		if((i & 7) == 7) fprintf(f, "\n");
	}
	if(np2 & 7) fprintf(f, "\n");

	fprintf(f, "tr2ch\n");
	if(!np2) fprintf(f, "\t.byt\t0\n");
	for(i = 0; i < np2; i++) {
		fprintf(f, "%s", (i & 7)? "," : "\t.byt\t");
		put_char_byte(f, tr[p2[i]]->translit[1]);
		if((i & 7) == 7) fprintf(f, "\n");
	}
	if(np2 & 7) fprintf(f, "\n");
}

// Emit the trhi/trlo/trc0 arrays read by translit in a2_frontend.s,
// along with the NTRANS and TRLOW constants that bound its two scans.
//
// The table is sorted by codepoint, so every entry below U+0100 comes first
// and the high bytes they would contribute to trhi are all zero.

void write_translit(const char *filename) {
	struct entry **tr;
	FILE *f;
	int *p2;
	int i, ntr = 0, np2 = 0, trlow;

	tr = malloc(nentry * sizeof(struct entry *));
	for(i = 0; i < nentry; i++) {
		if(!entries[i].translit[0]) continue;
		if(entries[i].glyph > 0xffff) {
			fprintf(stderr, "U+%04X is outside the BMP, "
				"trhi/trlo hold 16-bit codepoints only\n",
				entries[i].glyph);
			exit(1);
		}
		tr[ntr++] = &entries[i];
	}

	if(!ntr) {
		fprintf(stderr, "no transliterations found in the font definition\n");
		exit(1);
	}

	if(ntr > MAXTRANS) {
		fprintf(stderr, "%d transliterations, at most %d fit\n", ntr, MAXTRANS);
		exit(1);
	}

	p2 = malloc(ntr * sizeof(int));
	for(i = 0; i < ntr; i++) {
		if(tr[i]->translit[1]) p2[np2++] = i;
	}

	for(trlow = 0; trlow < ntr && tr[trlow]->glyph < 0x100; trlow++);

	if(!trlow) {
		// translit enters its low scan with ldx #TRLOW-1 and its high
		// scan leaves x at $ff on the way out, so both misbehave here.
		fprintf(stderr, "no transliterations below U+0100\n");
		exit(1);
	}

	f = fopen(filename, "w");
	if(!f) {
		perror(filename);
		exit(1);
	}

	fprintf(f, "; Generated by mkfont from fontdef.txt - do not edit.\n");
	fprintf(f, "; %d codepoints, sorted by codepoint.\n", ntr);
	fprintf(f, "; The first %d are below U+0100, so trhi omits their zeroes.\n", trlow);
	fprintf(f, "; %d have a second character, listed at the end.\n", np2);
	fprintf(f, "\nNTRANS\t=\t%d\nTRLOW\t=\t%d\n\n", ntr, trlow);
	put_table(f, "trhinz", tr, trlow, ntr, 0);
	fprintf(f, "trhi\t=\ttrhinz-TRLOW\n");
	put_table(f, "trlo", tr, 0, ntr, 1);
	put_table(f, "trc0", tr, 0, ntr, 2);
	put_pairs(f, tr, p2, np2);

	if(fclose(f)) {
		perror(filename);
		exit(1);
	}

	free(p2);
	free(tr);
}

void usage(const char *me) {
	fprintf(stderr,
		"usage: %s [-t translit.s] <fontdef.txt >font.bin\n"
		"\t-t FILE\twrite the transliteration table to FILE instead of\n"
		"\t\tthe font binary to stdout\n",
		me);
	exit(1);
}

int main(int argc, char **argv) {
	char buf[64];
	const char *translitfile = 0;
	int glyph;
	struct entry *e = 0;
	int i, x, y = 0;
	uint8_t bits;

	for(i = 1; i < argc; i++) {
		if(!strcmp(argv[i], "-t") && i + 1 < argc) {
			translitfile = argv[++i];
		} else {
			usage(argv[0]);
		}
	}

	while(fgets(buf, sizeof(buf), stdin)) {
		if(1 == sscanf(buf, "+%x", &glyph)) {
			e = add(glyph);
			parse_translit(e, buf);
			y = 0;
			if (glyph < 0x80 && e->translit[0]) {
				fprintf(stderr, "U+%04X: only extended chars can have transliterations\n", e->glyph);
				exit(1);
			}
			if (glyph >= 0x80 && !e->translit[0]) {
				fprintf(stderr, "Warning: U+%04X: missing transliteration\n", e->glyph);
			}
		} else if((buf[0] == '.' || buf[0] == '#') && e) {
			for(x = 0; x < 8; x++) {
				if(buf[x] == '#' && y < 8) {
					e->row[y] |= 0x80 >> x;
				}
			}
			y++;
			e->nrow = y;
		}
	}

	qsort(entries, nentry, sizeof(struct entry), cmp_entry);

	if(translitfile) {
		write_translit(translitfile);
		return 0;
	}

	if((e = find(0))) {
		for(i = 8; i < 128; i++) {
			for(y = 0; y < 8; y++) {
				basefont[i][y] = e->row[y];
			}
		}
	}

	for(i = 0; i < nentry; i++) {
		e = &entries[i];
		if(e->glyph < 128 && e->nrow) {
			for(y = 0; y < 8; y++) {
				basefont[e->glyph][y] = e->row[y];
			}
		}
	}

	// Replace chars 0..7 with a cursor sprite.
	for(y = 0; y < 21; y++) {
		for(x = 0; x < 3; x++) {
			if(y >= 0 && y <= 7 && x == 0) {
				bits = 0xfe;
			} else {
				bits = 0x00;
			}
			i = y * 3 + x;
			basefont[i / 8][i & 7] = bits;
		}
	}

	fwrite(basefont, 1024, 1, stdout);

	// A codepoint with a transliteration but no bitmap is a translit-only
	// entry and contributes no glyph to the font.

	for(i = 0; i < nentry; i++) {
		e = &entries[i];
		if(e->nrow && e->nrow != 8) {
			fprintf(stderr, "U+%04X should have exactly 8 rows "
				"if a glyph is present", e->glyph);
			return 1;
		}
		if(e->glyph >= 128 && e->nrow) {
			if(e->glyph > 0xffff) {
				fprintf(stderr, "U+%04X is outside the BMP, "
					"the font's extended table is indexed "
					"by 16-bit codepoint\n", e->glyph);
				return 1;
			}
			fputc((e->glyph >> 8) & 0xff, stdout);
			fputc((e->glyph >> 0) & 0xff, stdout);
			for(y = 0; y < 8; y++) {
				fputc(e->row[y], stdout);
			}
		}
	}

	return 0;
}
