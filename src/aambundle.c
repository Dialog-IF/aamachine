#include <assert.h>
#include <errno.h>
#include <getopt.h>
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
				fprintf(stderr, "Warning: Extended character %d (%s, U+%04x) found in dictionary word '%s'. This word will not be recognized in user input.\n",
					dict[j],
					unicode_to_utf8(unichar),
					unichar,
					print_n_characters_from(dict, wordstart, wordlength)
				);
			}
		}
	}
}

void trim_chunks(int align_writ) {
	uint32_t src = 12, dest = 12, size;
	uint8_t *chunk;
	char head[5];
	int pad;

	while(src < storysize) {
		chunk = story + src;
		memcpy(head, chunk, 4);
		head[4] = 0;
		size =
			(chunk[4] << 24) |
			(chunk[5] << 16) |
			(chunk[6] << 8) |
			(chunk[7] << 0);
		size = (8 + size + 1) & ~1;
		if(align_writ && !strcmp(head, "WRIT")) {
			pad = 0x100 - (dest & 0xff);
			assert(!(pad & 1));
			if(pad < 0xf0) {
				if(pad < 8) pad += 0x100;
				memmove(story + src + pad, story + src, storysize - src);
				storysize += pad;
				memcpy(chunk, "    ", 4);
				chunk[4] = 0;
				chunk[5] = 0;
				chunk[6] = (pad - 8) >> 8;
				chunk[7] = (pad - 8) & 0xff;
				memset(chunk + 8, 0, pad - 8);
				size = pad;
			}
		}
		if(strcmp(head, "FILE")) {
			if(dest != src) {
				memmove(story + dest, story + src, size);
			}
			dest += size;
		}
		src += size;
	}

	storysize = dest;
	story[4] = ((storysize - 8) >> 24) & 0xff;
	story[5] = ((storysize - 8) >> 16) & 0xff;
	story[6] = ((storysize - 8) >> 8) & 0xff;
	story[7] = ((storysize - 8) >> 0) & 0xff;
}

void usage(char *prgname) {
	fprintf(stderr, "Aa-machine tools " VERSION "\n");
	fprintf(stderr, "Copyright 2019-2026 Linus Akesson and the Dialog Project contributors.\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "Usage: %s [options] filename.aastory\n", prgname);
	fprintf(stderr, "\n");
	fprintf(stderr, "Options:\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "--version   -V    Display the program version.\n");
	fprintf(stderr, "--help      -h    Display this information.\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "--output    -o    Set output directory/file name.\n");
	fprintf(stderr, "--target    -t    Select target (web, c64, apple2, web:story).\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "Targets:\n");
	fprintf(stderr, "web (default)     Directory with web interpreter.\n");
	fprintf(stderr, "c64               Directory with c64 disk image.\n");
	fprintf(stderr, "apple2            Directory with apple2 disk images.\n");
	fprintf(stderr, "web:story         Just story.js for the web interpreter.\n");
	exit(1);
}

int main(int argc, char **argv) {
	struct option longopts[] = {
		{"help", 0, 0, 'h'},
		{"version", 0, 0, 'V'},
		{"output", 1, 0, 'o'},
		{"target", 1, 0, 't'},
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
			case '?':
			case 'h':
				usage(prgname);
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
					fprintf(stderr, "Unimplemented option '%c'\n", opt);
					exit(1);
				}
				break;
		}
	} while(opt >= 0);

	if(optind >= argc) {
		usage(prgname);
	}

	storyfile = argv[optind];

	if(strcmp(target, "web")
	&& strcmp(target, "web:story")
	&& strcmp(target, "c64")
	&& strcmp(target, "apple2")) {
		fprintf(stderr, "Unsupported target \"%s\".\n", target);
		exit(1);
	}

	if(!dirname) {
		if(!strcmp(target, "web:story")) {
			dirname = "story.js";
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
		fprintf(stderr, "%s: %s\n", argv[optind], strerror(errno));
		exit(1);
	}
	if(12 != fread(buf, 1, 12, f)
	|| memcmp(buf, "FORM", 4)
	|| memcmp(buf + 8, "AAVM", 4)) {
		fprintf(stderr, "Error: Bad or missing file header.\n");
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
		fprintf(stderr, "Failed to read all of '%s': %s\n", argv[optind], strerror(errno));
		exit(1);
	}

	fclose(f);

	if(story[20] > VER_MAJOR || (story[20] == VER_MAJOR && story[21] > VER_MINOR)) {
		fprintf(stderr, "Unsupported story file version: %d.%d is more than %d.%d\n", story[20], story[21], VER_MAJOR, VER_MINOR);
		exit(1);
	}

	if(!strcmp(target, "web:story")) {
		bundle_web_story(dirname);
	} else {
		if(mkdir(dirname, 0777) && errno != EEXIST) {
			fprintf(stderr, "%s: %s\n", dirname, strerror(errno));
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

	return 0;
}
