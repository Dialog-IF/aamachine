#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "aambundle.h"

#include "table_css.h"
#include "table_engine.h"
#include "table_front.h"
#include "table_jquery.h"
#include "table_play.h"

static struct tabledef {
	uint8_t 	*data;
	int		size;
	char		*path;
} webtables[] = {
	{table_engine,	sizeof(table_engine),	"/resources/aaengine.js"},
	{table_front,	sizeof(table_front),	"/resources/frontend.js"},
	{table_jquery,	sizeof(table_jquery),	"/resources/jquery.js"},
	{table_css,	sizeof(table_css),	"/resources/style.css"},
	{table_play,	sizeof(table_play),	"/play.html"},
};

static const char *encode = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

static char storyname[48];

void file_visitor(char *dirname, uint8_t *chunk, uint32_t size) {
	FILE *f;
	int namelen = strlen((char *) chunk);
	int len = strlen(dirname) + 64 + namelen;
	char fname[len];

	snprintf(fname, len, "%s/resources/%s", dirname, chunk);
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

void bundle_web(char *dirname) {
	char *filename;
	int fnsize, i;
	uint32_t n, pos;
	uint8_t buf[3], out[4];
	FILE *outf;

	fnsize = strlen(dirname) + 64;
	filename = malloc(fnsize);

	snprintf(filename, fnsize, "%s/resources", dirname);
	if(mkdir(filename, 0777)) {
		fprintf(stderr, "%s: %s\n", filename, strerror(errno));
		exit(1);
	}

	for(i = 0; i < sizeof(webtables)/sizeof(*webtables); i++) {
		strcpy(filename, dirname);
		strcat(filename, webtables[i].path);
		if(!(outf = fopen(filename, "wb"))) {
			fprintf(stderr, "%s: %s\n", filename, strerror(errno));
			exit(1);
		}
		if(1 != fwrite(webtables[i].data, webtables[i].size, 1, outf)) {
			fprintf(stderr, "%s: write error\n", filename);
			exit(1);
		}
		fclose(outf);
	}

	visit_chunks(storyname, sizeof(storyname), file_visitor);

	snprintf(filename, fnsize, "%s/resources/%s.aastory", dirname, storyname);
	if(!(outf = fopen(filename, "wb"))) {
		fprintf(stderr, "%s: %s\n", filename, strerror(errno));
		exit(1);
	}
	if(1 != fwrite(story, storysize, 1, outf)) {
		fprintf(stderr, "%s: write error\n", filename);
		exit(1);
	}
	fclose(outf);

	trim_chunks(0);

	snprintf(filename, fnsize, "%s/resources/story.js", dirname);

	outf = fopen(filename, "wb");
	if(!outf) {
		fprintf(stderr, "%s: %s\n", filename, strerror(errno));
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
}
