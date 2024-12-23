/* This file is part of the Aa-machine 6502 engine by Linus Akesson. */

#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAXSIZE (20*1024)

#define TARGET_ADDR 0x1100
#define DECR_ADDR 0x8000

uint8_t data[MAXSIZE];
int datasz;

struct point {
	uint16_t	cost;
	uint16_t	offset;
	uint8_t		length;
} point[MAXSIZE + 1];

uint8_t decruncher[2048];
int decrsz;

uint8_t stream[MAXSIZE];

int main(int argc, char **argv) {
	FILE *f;
	struct point best;
	uint16_t cost;
	int i, j, k, n, offs;
	int verbose = 0;

	if(argc > 1 && !strcmp(argv[1], "-v")) {
		verbose = 1;
		argc--;
		argv++;
	}

	if(argc != 3) {
		fprintf(stderr, "Usage: %s [-v] payload decruncher\n", argv[0]);
		exit(1);
	}

	f = fopen(argv[1], "rb");
	if(!f) {
		fprintf(stderr, "%s: %s\n", argv[1], strerror(errno));
		exit(1);
	}
	datasz = fread(data, 1, MAXSIZE, f);
	fclose(f);

	for(i = 1; i <= datasz; i++) {
		// We've already decrunched all data from i to datasz,
		// so there are i bytes left.
		// We can always read one byte of literal data.
		best.offset = 0;
		best.length = 1;
		best.cost = 2 + point[i - 1].cost;
		// We could read a larger chunk of literal data.
		for(n = 2; n <= 128 && n <= i; n++) {
			cost = 1 + n + point[i - n].cost;
			if(cost <= best.cost) {
				best.offset = 0;
				best.length = n;
				best.cost = cost;
			}
		}
		// Or we could copy earlier data.
		for(offs = 1; offs <= 256; offs++) {
			for(n = 0; n < 34; n++) {
				if(i - 1 - n < 0
				|| i - 1 - n + offs >= datasz
				|| data[i - 1 - n] != data[i - 1 - n + offs]) {
					break;
				}
			}
			while(n >= 2) {
				cost = 0xffff;
				if(n >= 2 && n <= 4 && offs <= 32) {
					cost = 1 + point[i - n].cost;
				} else if(n >= 3) {
					cost = 2 + point[i - n].cost;
				}
				if(cost < best.cost) {
					best.offset = offs;
					best.length = n;
					best.cost = cost;
				}
				n--;
			}
		}
		memcpy(point + i, &best, sizeof(struct point));
	}

	j = MAXSIZE;
	for(i = datasz; i > 0; ) {
		if(point[i].offset) {
			if(verbose) fprintf(stderr, "copy %d %d\n", point[i].length, point[i].offset);
			if(point[i].length <= 4 && point[i].offset <= 32) {
				assert(j >= 1);
				stream[--j] = 0x80 | ((point[i].length - 1) << 5) | (point[i].offset - 1);
			} else {
				assert(point[i].length >= 3);
				assert(j >= 2);
				stream[--j] = 0x80 | (point[i].length - 3);
				stream[--j] = point[i].offset - 1;
			}
		} else {
			if(verbose) fprintf(stderr, "read %d\n", point[i].length);
			assert(j >= 1 + point[i].length);
			stream[--j] = point[i].length - 1;
			for(k = 0; k < point[i].length; k++) {
				stream[--j] = data[i - 1 - k];
			}
		}
		i -= point[i].length;
	}

	f = fopen(argv[2], "rb");
	if(!f) {
		fprintf(stderr, "%s: %s\n", argv[2], strerror(errno));
		exit(1);
	}
	decrsz = fread(decruncher, 1, sizeof(decruncher), f);
	fclose(f);

	fprintf(stderr, "Compressed %d -> %d (%.02f%%)\n",
		datasz,
		MAXSIZE - j,
		(MAXSIZE - j) * 100.0 / datasz);

	decruncher[decrsz - 4] = (TARGET_ADDR + datasz) & 0xff;
	decruncher[decrsz - 3] = (TARGET_ADDR + datasz) >> 8;
	decruncher[decrsz - 2] = (DECR_ADDR + decrsz + (MAXSIZE - j)) & 0xff;
	decruncher[decrsz - 1] = (DECR_ADDR + decrsz + (MAXSIZE - j)) >> 8;

	fwrite(decruncher, 1, decrsz, stdout);
	fwrite(stream + j, 1, MAXSIZE - j, stdout);

	return 0;
}
