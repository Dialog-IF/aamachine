#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct entry {
	uint32_t	glyph;
	uint8_t		row[8];
};

struct entry *entries;
int nentry, nalloc;

uint8_t basefont[128][8];

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

int main() {
	char buf[64];
	int glyph;
	struct entry *e = 0;
	int i, x, y = 0;
	uint8_t bits;

	while(fgets(buf, sizeof(buf), stdin)) {
		if(1 == sscanf(buf, "+%x", &glyph)) {
			e = add(glyph);
			y = 0;
		} else if((buf[0] == '.' || buf[0] == '#') && e && y < 8) {
			for(x = 0; x < 8; x++) {
				if(buf[x] == '#') {
					e->row[y] |= 0x80 >> x;
				}
			}
			y++;
		}
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
		if(e->glyph < 128) {
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

	qsort(entries, nentry, sizeof(struct entry), cmp_entry);

	fwrite(basefont, 1024, 1, stdout);

	for(i = 0; i < nentry; i++) {
		e = &entries[i];
		if(e->glyph >= 128) {
			fputc((e->glyph >> 8) & 0xff, stdout);
			fputc((e->glyph >> 0) & 0xff, stdout);
			for(y = 0; y < 8; y++) {
				fputc(e->row[y], stdout);
			}
		}
	}

	return 0;
}
