#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "aambundle.h"

#include "table_c64drive.h"
#include "table_c64load.h"
#include "table_c64terp.h"

#define INTERLEAVE 11

static char storyname[48];

static uint8_t image[683][256];
static uint8_t available[683];

static int nsector[35] = {
	21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21,
	19, 19, 19, 19, 19, 19, 19,
	18, 18, 18, 18, 18, 18,
	17, 17, 17, 17, 17
};

static int trackoffs[35];

int log2phy(int linear) {
	int t, s, phy;

	for(t = 0; t < 35; t++) {
		if(t != 18 - 1) {
			if(linear < nsector[t]) break;
			linear -= nsector[t];
		}
	}
	assert(t < 35);
	assert(linear < nsector[t]);

	s = 0;
	while(linear--) {
		s += INTERLEAVE;
		if(s >= nsector[t]) {
			s -= nsector[t];
		}
	}

	phy = s;
	while(t) {
		phy += nsector[--t];
	}

	return phy;
}

void write_bam() {
	int t, s, i, nfree = 0;
	uint8_t bits[4];
	uint8_t *bam;
	char ch;

	bam = image[trackoffs[18 - 1] + 0];

	bam[0] = 18;
	bam[1] = 1;
	bam[2] = 0x41;

	memset(bam + 144, 0xa0, 27);
	for(i = 0; i < 16 && storyname[i]; i++) {
		ch = storyname[i];
		if(ch >= 'a' && ch <= 'z') ch ^= 0x20;
		if(ch == '-') ch = 0x20;
		bam[144 + i] = ch;
	}

	bam[162] = 'A';
	bam[163] = 'A';

	bam[165] = 0x32;
	bam[166] = 0x41;

	for(t = 0; t < 35; t++) {
		memset(bits, 0, sizeof(bits));
		for(s = 0; s < nsector[t]; s++) {
			if(available[trackoffs[t] + s]) {
				bits[0]++;
				bits[1 + s / 8] |= 1 << (s & 7);
				if(t != 18 - 1) nfree++;
			}
		}
		for(i = 0; i < 4; i++) {
			image[trackoffs[18 - 1] + 0][4 + 4 * t + i] = bits[i];
		}
	}

	fprintf(stderr, "%d blocks free\n", nfree);
}

void bundle_c64(char *dirname) {
	char *filename, ch;
	int fnsize, size;
	int i, j, pos;
	int terpsectors, terploc;
	FILE *outf;

	j = 0;
	for(i = 0; i < 35; i++) {
		trackoffs[i] = j;
		j += nsector[i];
	}
	assert(j == 683);
	memset(available, 1, j);

	visit_chunks(storyname, sizeof(storyname), 0);
	trim_chunks(1);

	fnsize = strlen(dirname) + strlen(storyname) + 64;
	filename = malloc(fnsize);

	terpsectors = (sizeof(table_c64terp) + 0xff) >> 8;
	terploc = 664 - terpsectors;
	for(i = 0; i < terpsectors; i++) {
		j = log2phy(terploc + i);
		assert(available[j]);
		available[j] = 0;
		if(i == terpsectors - 1) {
			size = sizeof(table_c64terp) - i * 256;
		} else {
			size = 256;
		}
		memcpy(image[j], table_c64terp + i * 256, size);
	}

	i = 0;
	pos = 0;
	while(pos < storysize) {
		size = storysize - pos;
		if(size > 256) size = 256;
		j = log2phy(i++);
		if(!available[j]) {
			fprintf(stderr, "Story too large!\n");
			exit(1);
		}
		available[j] = 0;
		memcpy(image[j], story + pos, size);
		pos += size;
	}

	// Directory track:
	// 0 = bam
	// 1 = dir
	// 2, 10 = drivecode
	// 3, 11 = loader
	// 5 = copy of first story block (with HEAD chunk)

	image[trackoffs[18 - 1] + 1][1] = 0xff;
	image[trackoffs[18 - 1] + 1][2 + 0] = 0x82;
	image[trackoffs[18 - 1] + 1][2 + 1] = 18;
	image[trackoffs[18 - 1] + 1][2 + 2] = 3;
	image[trackoffs[18 - 1] + 1][2 + 28] = 3;
	memset(&image[trackoffs[18 - 1] + 1][2 + 3], 0xa0, 16);

	for(i = 0; i < 16 && storyname[i]; i++) {
		ch = storyname[i];
		if(ch >= 'a' && ch <= 'z') ch ^= 0x20;
		if(ch == '-') ch = 0x20;
		image[trackoffs[18 - 1] + 1][2 + 3 + i] = ch;
	}

	memcpy(image[trackoffs[18 - 1] + 2], table_c64drive, 256);
	memcpy(image[trackoffs[18 - 1] + 10], table_c64drive + 256, 256);

	memcpy(image[trackoffs[18 - 1] + 3] + 2, table_c64load, 254);
	image[trackoffs[18 - 1] + 3][0] = 18;
	image[trackoffs[18 - 1] + 3][1] = 11;
	memcpy(image[trackoffs[18 - 1] + 11] + 2, table_c64load + 254, sizeof(table_c64load) - 254);
	j = sizeof(table_c64load) - 254;
	image[trackoffs[18 - 1] + 11][2 + j - 3] = terploc & 0xff;
	image[trackoffs[18 - 1] + 11][2 + j - 2] = terploc >> 8;
	image[trackoffs[18 - 1] + 11][2 + j - 1] = terpsectors;
	image[trackoffs[18 - 1] + 11][1] = j + 1;

	memcpy(image[trackoffs[18 - 1] + 5], image[0], 256);

	available[trackoffs[18 - 1] + 0] = 0;
	available[trackoffs[18 - 1] + 1] = 0;
	available[trackoffs[18 - 1] + 2] = 0;
	available[trackoffs[18 - 1] + 10] = 0;
	available[trackoffs[18 - 1] + 3] = 0;
	available[trackoffs[18 - 1] + 11] = 0;
	available[trackoffs[18 - 1] + 5] = 0;

	write_bam();

	snprintf(filename, fnsize, "%s/%s.d64", dirname, storyname);
	outf = fopen(filename, "wb");
	if(!outf) {
		fprintf(stderr, "%s: %s", filename, strerror(errno));
		exit(1);
	}
	fwrite(image, 1, sizeof(image), outf);
	fclose(outf);
}
