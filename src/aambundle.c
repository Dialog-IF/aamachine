#include <errno.h>
#include <getopt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

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
	int opt, i, n;
	FILE *f, *outf;
	uint8_t buf[12], out[4];
	char *jsdataname, *filename;

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
	fseek(f, 0, SEEK_SET);

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

	do {
		n = fread(buf, 1, 3, f);
		if(n) {
			for(i = n; i < 3; i++) buf[i] = 0;
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
	fclose(f);

	return 0;
}
