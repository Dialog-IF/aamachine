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

void visit_chunks(char *storyname, int storynamesize, file_visitor_t file_visitor) {
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
						if(snamelen < storynamesize - 1) {
							if((ch >= 'a' && ch <= 'z')
							|| (ch >= 'A' && ch <= 'Z')
							|| (ch >= '0' && ch <= '9')) {
								storyname[snamelen++] = ch;
							} else {
								storyname[snamelen++] = '-';
							}
						}
					}
					storyname[snamelen] = 0;
				} else {
					while(*chunk++);
				}
			}
		} else if(!strcmp(head, "FILE")) {
			if(file_visitor) {
				file_visitor(dirname, chunk, size);
			}
		}
		pos += (8 + size + 1) & ~1;
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
	fprintf(stderr, "Copyright 2019 Linus Akesson.\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "Usage: %s [options] filename.aastory\n", prgname);
	fprintf(stderr, "\n");
	fprintf(stderr, "Options:\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "--version   -V    Display the program version.\n");
	fprintf(stderr, "--help      -h    Display this information.\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "--output    -o    Set output directory name.\n");
	fprintf(stderr, "--target    -t    Select target (web, c64).\n");
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

	if(strcmp(target, "web") && strcmp(target, "c64")) {
		fprintf(stderr, "Unsupported target \"%s\".\n", target);
		exit(1);
	}

	if(!dirname) {
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

	if(story[20] != 0 || story[21] > 3) {
		fprintf(stderr, "Unsupported story file version %d.%d\n", story[20], story[21]);
		exit(1);
	}

	if(mkdir(dirname, 0777)) {
		fprintf(stderr, "%s: %s\n", dirname, strerror(errno));
		exit(1);
	}

	if(!strcmp(target, "web")) {
		bundle_web(dirname);
	} else if(!strcmp(target, "c64")) {
		bundle_c64(dirname);
	}

	return 0;
}
