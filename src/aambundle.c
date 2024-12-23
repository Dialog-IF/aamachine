#include <errno.h>
#include <getopt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "aavm.h"

#include "table_engine.h"
#include "table_front.h"
#include "table_jquery.h"
#include "table_css.h"
#include "table_play.h"

#if (defined(_WIN32) || defined(__WIN32__))
#define mkdir(Path, Mode) mkdir(Path)
#endif

struct tabledef {
	uint8_t 	*data;
	int		size;
	char		*path;
} tables[] = {
	{table_engine,	sizeof(table_engine),	"/resources/aaengine.js"},
	{table_front,	sizeof(table_front),	"/resources/frontend.js"},
	{table_jquery,	sizeof(table_jquery),	"/resources/jquery.js"},
	{table_css,	sizeof(table_css),	"/resources/style.css"},
	{table_play,	sizeof(table_play),	"/play.html"},
};

const char *encode = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

uint8_t *story;
uint32_t storysize;
uint8_t storyname[48];
int snamelen = 0;

void visit_chunks(char *outname) {
	uint32_t pos = 12, size;
	uint8_t *chunk;
	char head[5], ch;
	int n, i;
	FILE *f;

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
						if(snamelen < sizeof(storyname) - 1) {
							if((ch >= 'a' && ch <= 'z')
							|| (ch >= 'A' && ch <= 'Z')
							|| (ch >= '0' && ch <= '9')) {
								storyname[snamelen++] = ch;
							} else {
								storyname[snamelen++] = '-';
							}
						}
					}
				} else {
					while(*chunk++);
				}
			}
		} else if(!strcmp(head, "FILE")) {
			int namelen = strlen((char *) chunk);
			int len = strlen(outname) + 64 + namelen;
			char fname[len];
			snprintf(fname, len, "%s/resources/%s", outname, chunk);
			if(!(f = fopen(fname, "wb"))) {
				fprintf(stderr, "%s: %s\n", fname, strerror(errno));
				exit(1);
			}
			if(1 != fwrite(chunk + namelen + 1, size - namelen - 1, 1, f)) {
				fprintf(stderr, "%s: write error\n", fname);
				exit(1);
			}
			fclose(f);
		}
		pos += (8 + size + 1) & ~1;
	}
}

void trim_chunks() {
	uint32_t src = 12, dest = 12, size;
	uint8_t *chunk;
	char head[5];

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
		if(strcmp(head, "FILE")) {
			if(dest != src) {
				memmove(chunk + dest, chunk + src, size);
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
	fprintf(stderr, "--output    -o    Set output filename.\n");
	fprintf(stderr, "--format    -t    Set output format (dir, js).\n");
	exit(1);
}

int main(int argc, char **argv) {
	struct option longopts[] = {
		{"help", 0, 0, 'h'},
		{"version", 0, 0, 'V'},
		{"output", 1, 0, 'o'},
		{"format", 1, 0, 't'},
		{0, 0, 0, 0}
	};
	char *prgname = argv[0];
	char *outname = 0;
	char *format = "dir";
	int opt, i;
	FILE *f, *outf;
	uint8_t buf[12], out[4];
	char *jsdataname, *filename;
	uint32_t n, pos;

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
				outname = strdup(optarg);
				break;
			case 't':
				format = strdup(optarg);
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

	if(strcmp(format, "js") && strcmp(format, "dir")) {
		fprintf(stderr, "Unsupported output format \"%s\".\n", format);
		exit(1);
	}

	if(!outname) {
		outname = malloc(strlen(argv[optind]) + 8);
		strcpy(outname, argv[optind]);
		for(i = strlen(outname) - 1; i >= 0; i--) {
			if(outname[i] == '.') break;
		}
		if(i < 0) {
			i = strlen(outname);
		}
		if(!strcmp(format, "dir")) {
			outname[i] = 0;
		} else {
			outname[i++] = '.';
			strcpy(outname + i, format);
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

	story = malloc(storysize);
	if(storysize != fread(story, 1, storysize, f)) {
		fprintf(stderr, "Failed to read all of '%s': %s\n", argv[optind], strerror(errno));
		exit(1);
	}

	fclose(f);

	if(!strcmp(format, "dir")) {
		int size = strlen(outname) + 64;
		filename = malloc(size);

		if(mkdir(outname, 0777)) {
			fprintf(stderr, "%s: %s\n", outname, strerror(errno));
			exit(1);
		}

		snprintf(filename, size, "%s/resources", outname);
		if(mkdir(filename, 0777)) {
			fprintf(stderr, "%s: %s\n", filename, strerror(errno));
			exit(1);
		}

		for(i = 0; i < sizeof(tables)/sizeof(*tables); i++) {
			strcpy(filename, outname);
			strcat(filename, tables[i].path);
			if(!(outf = fopen(filename, "wb"))) {
				fprintf(stderr, "%s: %s\n", filename, strerror(errno));
				exit(1);
			}
			if(1 != fwrite(tables[i].data, tables[i].size, 1, outf)) {
				fprintf(stderr, "%s: write error\n", filename);
				exit(1);
			}
			fclose(outf);
		}

		visit_chunks(outname);

		snprintf(filename, size, "%s/resources/%s.aastory", outname, storyname);
		if(!(outf = fopen(filename, "wb"))) {
			fprintf(stderr, "%s: %s\n", filename, strerror(errno));
			exit(1);
		}
		if(1 != fwrite(story, storysize, 1, outf)) {
			fprintf(stderr, "%s: write error\n", filename);
			exit(1);
		}
		fclose(outf);

		trim_chunks();

		snprintf(filename, size, "%s/resources/story.js", outname);
		jsdataname = filename;
	} else {
		jsdataname = outname;
	}

	outf = fopen(jsdataname, "wb");
	if(!outf) {
		fprintf(stderr, "%s: %s\n", jsdataname, strerror(errno));
		exit(1);
	}

	fprintf(outf, "window.aastory = '");

	pos = 0;
	do {
		n = storysize - pos;
		if(n > 3) n = 3;
		if(n) {
			for(i = 0; i < n; i++) {
				buf[i] = story[pos++];
			}
			for(; i < 3; i++) {
				buf[i] = 0;
			}
			out[0] = buf[0] >> 2;
			out[1] = ((buf[0] & 3) << 4) | (buf[1] >> 4);
			out[2] = ((buf[1] & 15) << 2) | (buf[2] >> 6);
			out[3] = buf[2] & 0x3f;
			if(n == 1) {
				out[2] = 64;
				out[3] = 64;
			} else if(n == 2) {
				out[3] = 64;
			}
			for(i = 0; i < 4; i++) {
				fputc(encode[out[i]], outf);
			}
		}
	} while(n == 3);

	fprintf(outf, "';\n");

	fclose(outf);

	return 0;
}
