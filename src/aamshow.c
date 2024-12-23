#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "aavm.h"
#include "crc32.h"

#define MAXCHUNK 32

#define BYTESPERLINE 7

struct chunk {
	char		name[5];
	uint32_t	size;
	uint8_t		*data;
} chunk[MAXCHUNK];
int nchunk;

uint8_t *extchars;
uint32_t actual_crc;
int strshift;

typedef void (*decoder_func_t)(struct chunk *ch);

static struct chunk *findchunk(char *tag) {
	int i;

	for(i = 0; i < nchunk; i++) {
		if(!strcasecmp(chunk[i].name, tag)) {
			return chunk + i;
		}
	}

	return 0;
}

static uint32_t get32(uint8_t *buf) {
	return
		(buf[0] << 24) |
		(buf[1] << 16) |
		(buf[2] << 8) |
		(buf[3] << 0);
}

static uint16_t get16(uint8_t *buf) {
	return
		(buf[0] << 8) |
		(buf[1] << 0);
}

static void put_aachar(uint8_t aach) {
	uint32_t uchar;
	uint8_t *entry;

	if(aach < 0x80) {
		fputc(aach, stdout);
	} else {
		aach &= 0x7f;
		if(aach >= extchars[0]) {
			printf("??");
		} else {
			entry = extchars + 1 + aach * 5;
			uchar = (entry[2] << 16) | (entry[3] << 8) | (entry[4] << 0);
			if(uchar < 0x80) {
				fputc(uchar, stdout);
			} else if(uchar < 0x800) {
				fputc(0xc0 | (uchar >> 6), stdout);
				fputc(0x80 | ((uchar >> 0) & 0x3f), stdout);
			} else {
				fputc(0xe0 | (uchar >> 12), stdout);
				fputc(0x80 | ((uchar >> 6) & 0x3f), stdout);
				fputc(0x80 | ((uchar >> 0) & 0x3f), stdout);
			}
		}
	}
}

void decode_head(struct chunk *ch) {
	uint16_t heapsz, auxsz, ramsz, totalsz;
	int i;

	if(ch->size < 22) {
		printf("Error: HEAD: Bad size.\n");
		return;
	}

	printf("IFID:                  ");
	if(ch->size > 22) {
		printf("\"%s\"\n", (char *) ch->data + 22);
	} else {
		printf("(none)\n");
	}
	printf("Release:               %d\n", (ch->data[4] << 8) | ch->data[5]);
	printf("Serial number:         ");
	for(i = 0; i < 6; i++) {
		printf("%c", ch->data[6 + i]);
	}
	printf("\n");
	heapsz = (ch->data[16] << 8) | ch->data[17];
	auxsz = (ch->data[18] << 8) | ch->data[19];
	ramsz = (ch->data[20] << 8) | ch->data[21];
	totalsz = heapsz + auxsz + ramsz;
	printf("Heap area:             %d words\n", heapsz);
	printf("Aux area:              %d words\n", auxsz);
	printf("Random access area:    %d words\n", ramsz);
	printf("Total RAM requirement: %d words, %d bytes, %.1f kB (plus registers)\n",
		totalsz,
		2 * totalsz,
		2 * totalsz / 1024.0);
	printf("Content checksum:      %08x", get32(ch->data + 12));
	if(get32(ch->data + 12) == actual_crc) {
		printf(" (verified)\n");
	} else {
		printf(" (bad, expected %08x)\n", actual_crc);
	}
}

void decode_meta(struct chunk *ch) {
	int i, ptr = 1;
	uint8_t c;

	for(i = 0; i < ch->data[0]; i++) {
		switch(ch->data[ptr]) {
		case AAMETA_TITLE:	printf("Title:                 "); break;
		case AAMETA_AUTHOR:	printf("Author:                "); break;
		case AAMETA_NOUN:	printf("Noun:                  "); break;
		case AAMETA_RELDATE:	printf("Release date:          "); break;
		case AAMETA_COMPVER:	printf("Compiler:              "); break;
		case AAMETA_BLURB:	printf("Blurb:\n    "); break;
		default:		printf("Unknown 0x%02x:           ", ch->data[ptr]); break;
		}
		ptr++;
		while((c = ch->data[ptr++])) {
			if(c == '\n') {
				printf("\n    ");
			} else {
				put_aachar(c);
			}
		}
		printf("\n");
	}
}

void decode_look(struct chunk *ch) {
	int i, n, ptr;
	int did_header;
	uint8_t c;

	n = get16(ch->data);
	for(i = 0; i < n; i++) {
		ptr = get16(ch->data + 2 + i * 2);
		did_header = 0;
		while(ch->data[ptr]) {
			if(did_header) {
				printf("      ");
			} else {
				printf("%04x: ", i);
				did_header = 1;
			}
			while((c = ch->data[ptr++])) {
				fputc(c, stdout);
			}
			printf("\n");
		}
	}
}

static int put_obj(struct chunk *tagsch, int num) {
	int ptr, count = 0;
	uint8_t c;

	if(tagsch) {
		ptr = get16(tagsch->data + 2 + num * 2);
		while((c = tagsch->data[ptr++])) {
			put_aachar(c);
			count++;
		}
		return count;
	} else {
		return printf("%d", 1 + num);
	}
}

void decode_tags(struct chunk *ch) {
	int i, n;

	n = get16(ch->data);
	for(i = 0; i < n; i++) {
		printf("%04x: #", 1 + i);
		put_obj(ch, i);
		printf("\n");
	}
}

static void show_bitstream_decoder(uint8_t *table, int pos, int nextbit, uint32_t prefix) {
	int b;
	int i;
	uint8_t code;
	uint32_t bits;

	for(b = 0; b < 2; b++) {
		code = table[pos * 2 + b];
		if(code < 0x81) {
			printf("    ");
			bits = prefix | ((2 | b) << nextbit);
			for(i = 0; i < 32; i++) {
				if(bits > 1) {
					printf("%d", bits & 1);
					bits >>= 1;
				} else {
					printf(" ");
				}
			}
			if(code == 0x80) {
				printf("<end of string>\n");
			} else if(code == 0x5f) {
				printf("<extended char>\n");
			} else {
				printf("%02x ", code + 0x20);
				put_aachar(code + 0x20);
				printf("\n");
			}
		} else {
			show_bitstream_decoder(table, code & 0x7f, nextbit + 1, prefix | (b << nextbit));
		}
	}
}

static void show_endings_decoder(uint8_t *decoder, int pos, int indent) {
	int i;

	for(;;) {
		for(i = 0; i < indent; i++) {
			printf("    ");
		}
		if(decoder[pos] == 0x00) {
			printf("Fail\n");
			return;
		} else if(decoder[pos] == 0x01) {
			printf("Check\n");
			pos++;
		} else {
			put_aachar(decoder[pos]);
			printf(" ->\n");
			show_endings_decoder(decoder, decoder[pos + 1], indent + 1);
			pos += 2;
		}
	}
}

void decode_lang(struct chunk *ch) {
	int i, n, ptr;

	printf("Extended character set:\n");
	ptr = get16(ch->data + 2);
	n = ch->data[ptr++];
	for(i = 0; i < n; i++) {
		printf("    %02x: ", 0x80 | i);
		put_aachar(0x80 | i);
		printf(" lower=%02x upper=%02x\n",
			ch->data[ptr + 0],
			ch->data[ptr + 1]);
		ptr += 5;
	}

	printf("Bitstream decoder:\n");
	show_bitstream_decoder(ch->data + get16(ch->data + 0), 0, 0, 0);
	printf("Word endings decoder:\n");
	show_endings_decoder(ch->data + get16(ch->data + 4), 0, 1);
	printf("Stop characters:");
	ptr = get16(ch->data + 6);
	while(ch->data[ptr]) {
		printf(" ");
		put_aachar(ch->data[ptr++]);
	}
	printf("\n");
}

static int put_string(uint8_t *writ, uint8_t *decoder, uint32_t *addr) {
	int charcount = 2, nbit = 0, state = 0;
	uint8_t bits, code;

	printf("\"");
	for(;;) {
		if(!nbit) {
			bits = writ[(*addr)++];
			nbit = 8;
		}
		code = decoder[state * 2 + !!(bits & 0x80)];
		bits <<= 1;
		nbit--;
		if(code >= 0x81) {
			state = code & 0x7f;
		} else if(code == 0x80) {
			break;
		} else if(code == 0x5f) {
			code = 0x01;
			while(!(code & 0x80)) {
				if(!nbit) {
					bits = writ[(*addr)++];
					nbit = 8;
				}
				code <<= 1;
				code |= !!(bits & 0x80);
				bits <<= 1;
				nbit--;
			}
			put_aachar(code);
			charcount++;
			state = 0;
		} else {
			put_aachar(code + 0x20);
			charcount++;
			state = 0;
		}
	}
	printf("\"");

	return charcount;
}

void decode_writ(struct chunk *ch) {
	uint32_t addr = 0;
	struct chunk *langch = findchunk("LANG");
	uint8_t *decoder = langch->data + get16(langch->data + 0);

	while(addr < ch->size) {
		printf("%06x: ", addr);
		put_string(ch->data, decoder, &addr);
		printf("\n");
		if(addr < 254 && (addr & 1)) addr++;
	}
}

static int put_dict(struct chunk *dict, int num) {
	int j, len, ptr;

	len = dict->data[2 + num * 3 + 0];
	ptr = get16(dict->data + 2 + num * 3 + 1);
	for(j = 0; j < len; j++) {
		put_aachar(dict->data[ptr++]);
	}
	return len;
}

void decode_dict(struct chunk *ch) {
	int i, n;

	n = get16(ch->data);
	for(i = 0; i < n; i++) {
		printf("%04x: @", 0x2000 | i);
		put_dict(ch, i);
		printf("\n");
	}
}

void decode_maps(struct chunk *ch) {
	int i, nmap, j, k, n, id;
	uint8_t *map;
	uint16_t key, value;
	struct chunk *dictch = findchunk("DICT");
	struct chunk *tagsch = findchunk("TAGS");

	nmap = get16(ch->data);
	for(i = 0; i < nmap; i++) {
		printf("%04x:\n", i);
		map = ch->data + get16(ch->data + 2 + i * 2);
		n = get16(map);
		for(j = 0; j < n; j++) {
			key = get16(map + 2 + j * 4 + 0);
			value = get16(map + 2 + j * 4 + 2);
			if(key >= 0x2000 && key < 0x3e00) {
				printf("    @");
				k = put_dict(dictch, key & 0x1fff);
			} else if(key >= 3e00 && key < 0x3f00) {
				printf("    @");
				put_aachar(key & 0xff);
				k = 1;
			} else {
				printf("    %04x", key);
				k = 3;
			}
			while(k < 20) {
				printf(" ");
				k++;
			}
			if(value == 0x0000) {
				printf(" <anything>");
			} else if(value >= 0xe000) {
				printf(" #");
				put_obj(tagsch, value - 0xe001);
			} else {
				while((id = ch->data[value++])) {
					printf(" #");
					if(id >= 0xe0) {
						id = ((id & 0x1f) << 8) | ch->data[value++];
					}
					put_obj(tagsch, id - 1);
				}
			}
			printf("\n");
		}
	}
}

static void decode_init(struct chunk *ch) {
	int i, j, n, ltb, ltt, woffs, wsize, x;
	struct chunk *tagsch = findchunk("TAGS");

	n = get16(ch->data + 0);
	ltb = get16(ch->data + 2);
	ltt = get16(ch->data + 4);
	for(i = 0; i <= n; i++) {
		woffs = get16(ch->data + 6 + i * 2);
		if(i < n) {
			wsize = get16(ch->data + 6 + (i + 1) * 2) - woffs;
		} else {
			wsize = ltb - woffs;
		}
		printf("%04x ", woffs);
		if(i) {
			printf("#");
			j = put_obj(tagsch, i - 1) + 1;
		} else {
			j = printf("Global data");
		}
		while(j < 19) {
			printf(" ");
			j++;
		}
		x = 0;
		for(j = 0; j < wsize; j++) {
			if(x == 11) {
				printf("\n                        ");
				x = 0;
			}
			printf(" %04x", get16(ch->data + 6 + (woffs + j) * 2));
			x++;
		}
		printf("\n");
	}
	for(i = ltb; i < ltt; i += wsize) {
		printf("%04x ", i);
		j = printf("Long-term chunk");
		while(j < 19) {
			printf(" ");
			j++;
		}
		wsize = get16(ch->data + 6 + i * 2);
		x = 0;
		for(j = 0; j < wsize; j++) {
			if(x == 11) {
				printf("\n                        ");
				x = 0;
			}
			printf(" %04x", get16(ch->data + 6 + (i + j) * 2));
			x++;
		}
		printf("\n");
	}
}

static aaoper_t decode_oper(int type, uint8_t *code, uint32_t *addr) {
	uint32_t value;

	switch(type) {
	case AAO_NONE:
		return (aaoper_t) {AAO_NONE};
	case AAO_ZERO:
		return (aaoper_t) {AAO_ZERO};
	case AAO_BYTE:
		return (aaoper_t) {AAO_BYTE, code[(*addr)++]};
	case AAO_VBYTE:
		return (aaoper_t) {AAO_VBYTE, code[(*addr)++]};
	case AAO_WORD:
		value = code[(*addr)++];
		value = (value << 8) | code[(*addr)++];
		return (aaoper_t) {AAO_WORD, value};
	case AAO_INDEX:
		value = code[(*addr)++];
		if(value >= 0xc0) {
			value = ((value & 0x3f) << 8) | code[(*addr)++];
		}
		return (aaoper_t) {AAO_INDEX, value};
	case AAO_CODE:
		value = code[(*addr)++];
		if(value == 0) {
			return (aaoper_t) {AAO_CODE, 0};
		} else if(value & 0x80) {
			value = ((value & 0x7f) << 16) | (code[(*addr)++] << 8);
			value |= code[(*addr)++];
			return (aaoper_t) {AAO_CODE, value};
		} else if(value & 0x40) {
			value = ((value & 0x3f) << 8) | code[(*addr)++];
			if(value & 0x2000) {
				value |= 0xffffc000;
			}
			return (aaoper_t) {AAO_CODE, *addr + value};
		} else {
			return (aaoper_t) {AAO_CODE, *addr + value};
		}
	case AAO_STRING:
		value = code[(*addr)++];
		if(value >= 0xc0) {
			value = ((value & 0x3f) << 16) | (code[(*addr)++] << 8);
			value |= code[(*addr)++];
			return (aaoper_t) {AAO_STRING, value << strshift};
		} else if(value >= 0x80) {
			value = ((value & 0x3f) << 8) | code[(*addr)++];
			return (aaoper_t) {AAO_STRING, value << strshift};
		} else {
			return (aaoper_t) {AAO_STRING, value << 1};
		}
	case AAO_DEST:
		value = code[(*addr)++];
		if(value >= 0xc0) {
			return (aaoper_t) {AAO_VAR, value & 0x3f};
		} else if(value >= 0x80) {
			return (aaoper_t) {AAO_REG, value & 0x3f};
		} else if(value >= 0x40) {
			return (aaoper_t) {AAO_STORE_VAR, value & 0x3f};
		} else {
			return (aaoper_t) {AAO_STORE_REG, value & 0x3f};
		}
	case AAO_VALUE:
		value = code[(*addr)++];
		if(value >= 0xc0) {
			return (aaoper_t) {AAO_VAR, value & 0x3f};
		} else if(value >= 0x80) {
			return (aaoper_t) {AAO_REG, value & 0x3f};
		} else {
			value = (value << 8) | code[(*addr)++];
			return (aaoper_t) {AAO_CONST, value};
		}
	default:
		assert(0); exit(1);
	}
}

static int put_value(uint16_t v, struct chunk *dictch, struct chunk *tagsch) {
	int len;

	if(v == 0) {
		len = printf("0");
	} else if(tagsch && v <= get16(tagsch->data)) {
		len = printf("%d (#", v);
		len += put_obj(tagsch, v - 1);
		len += printf(")");
	} else if(v >= 0x2000 && v < 0x3e00) {
		len = printf("@");
		len += put_dict(dictch, v & 0x1fff);
	} else if(v >= 0x3e20 && v < 0x3f00) {
		printf("@");
		put_aachar(v & 0xff);
		len = 2;
	} else if(v == 0x3f00) {
		len = printf("[]");
	} else if(v >= 0x4000) {
		len = printf("(%d)", v & 0x3fff);
	} else {
		len = printf("0x%04x", v);
	}

	return len;
}

static void decode_code(struct chunk *ch) {
	uint8_t labelled[(ch->size + 7) / 8];
	uint32_t addr, instr, straddr;
	uint8_t op;
	aaoper_t aao[4];
	int i, nbyte, len;
	struct chunk *dictch = findchunk("DICT");
	struct chunk *tagsch = findchunk("TAGS");
	struct chunk *writch = findchunk("WRIT");
	struct chunk *langch = findchunk("LANG");
	uint8_t *decoder = langch->data + get16(langch->data + 0);

	memset(labelled, 0, (ch->size + 7) / 8);
	labelled[0] = 3;

	for(addr = 0; addr < ch->size; ) {
		instr = addr;
		op = ch->data[addr++];
		//printf("%06x %02x\n", instr, op);
		for(i = 0; i < 4; i++) {
			aao[i] = decode_oper(aaopinfo[op].oper[i], ch->data, &addr);
			if(aao[i].type == AAO_CODE) {
				if(aao[i].value < ch->size) {
					labelled[aao[i].value >> 3] |= 1 << (aao[i].value & 7);
				} else {
					printf("Warning: Invalid code pointer %06x in instruction at %06x\n",
						aao[i].value,
						instr);
				}
			}
		}
	}

	for(addr = 0; addr < ch->size; ) {
		if(labelled[addr >> 3] & 1 << (addr & 7)) {
			if(addr) printf("\n");
			printf("L%06x: ", addr);
		} else {
			printf("         ");
		}
		instr = addr;
		op = ch->data[addr++];
		for(i = 0; i < 4; i++) {
			aao[i] = decode_oper(aaopinfo[op].oper[i], ch->data, &addr);
		}
		nbyte = addr - instr;
		for(i = 0; i < nbyte && i < BYTESPERLINE; i++) {
			printf("%02x ", ch->data[instr + i]);
		}
		while(i < BYTESPERLINE) {
			printf("   ");
			i++;
		}
		if(op == AA_EXT0) {
			if(aao[0].value < AAEXT0_N) {
				len = printf("%s", aaext0name[aao[0].value]);
			} else {
				len = printf("%s", "ext0 ??");
			}
		} else {
			len = printf("%s", aaopinfo[op].name);
		}
		while(len < 19) {
			printf(" ");
			len++;
		}
		for(i = 0; i < 4; i++) {
			if(aao[i].type != AAO_NONE && op != AA_EXT0) {
				if(i) printf(", ");
				switch(aao[i].type) {
					case AAO_ZERO:
						len = printf("0");
						break;
					case AAO_BYTE:
						len = printf("%d", aao[i].value);
						break;
					case AAO_VBYTE:
						len = put_value(aao[i].value, dictch, tagsch);
						break;
					case AAO_WORD:
						if(op == AA_TRACEPOINT) {
							len = printf("%d", aao[i].value);
						} else {
							len = put_value(aao[i].value, dictch, tagsch);
						}
						break;
					case AAO_INDEX:
						len = printf("%d", aao[i].value);
						break;
					case AAO_CONST:
						len = put_value(aao[i].value, dictch, tagsch);
						break;
					case AAO_REG:
						if(aaopinfo[op].oper[i] == AAO_DEST) {
							printf("=");
							len = 1;
						} else {
							len = 0;
						}
						len += printf("R%02x", aao[i].value);
						break;
					case AAO_VAR:
						if(aaopinfo[op].oper[i] == AAO_DEST) {
							printf("=");
							len = 1;
						} else {
							len = 0;
						}
						len += printf("V%02x", aao[i].value);
						break;
					case AAO_STORE_REG:
						len = printf(">R%02x", aao[i].value);
						break;
					case AAO_STORE_VAR:
						len = printf(">V%02x", aao[i].value);
						break;
					case AAO_CODE:
						if(aao[i].value) {
							len = printf("L%06x", aao[i].value);
						} else {
							len = printf("fail");
						}
						break;
					case AAO_STRING:
						straddr = aao[i].value;
						len = put_string(writch->data, decoder, &straddr);
						break;
					default:
						len = 0;
				}
			}
		}
		printf("\n");
		i = BYTESPERLINE;
		if(i < nbyte) {
			printf("         ");
			while(i < nbyte) {
				printf("%02x ", ch->data[instr + i]);
				i++;
			}
			printf("\n");
		}
	}
}

struct decoder {
	decoder_func_t	func;
	char		name[5];
} decoder[] = {
	{decode_head, "HEAD"},
	{decode_meta, "META"},
	{decode_look, "LOOK"},
	{decode_tags, "TAGS"},
	{decode_lang, "LANG"},
	{decode_writ, "WRIT"},
	{decode_dict, "DICT"},
	{decode_maps, "MAPS"},
	{decode_init, "INIT"},
	{decode_code, "CODE"},
	{0}
};

static void list_chunks() {
	int i;

	printf("The following chunks are present:\n");
	for(i = 0; i < nchunk; i++) {
		printf("  %s %6d bytes %7.1f kB\n",
			chunk[i].name,
			chunk[i].size,
			chunk[i].size / 1024.0);
	}
}

static void crc_chunk(char *name) {
	struct chunk *ch = findchunk(name);
	uint32_t i;

	if(!ch) {
		fprintf(stderr, "Warning: Missing %s chunk.\n", name);
	} else {
		for(i = 0; i < ch->size; i++) {
			actual_crc =
				crc32_table[((actual_crc) & 0xff) ^ ch->data[i]]
				^ ((actual_crc) >> 8);
		}
	}
}

int main(int argc, char **argv) {
	FILE *f;
	uint8_t header[12];
	uint32_t formsz, offset, padded;
	int i, j, k;
	struct chunk *ch;

	aavm_init();

	if(argc < 2) {
		fprintf(stderr, "Aa-machine tools " VERSION "\n");
		fprintf(stderr, "Copyright 2019 Linus Akesson.\n");
		fprintf(stderr, "Usage: %s filename.aastory [chunk ...]\n", argv[0]);
		exit(1);
	}

	f = fopen(argv[1], "rb");
	if(!f) {
		fprintf(stderr, "%s: %s\n", argv[1], strerror(errno));
		exit(1);
	}

	if(12 != fread(header, 1, 12, f)
	|| memcmp(header, "FORM", 4)
	|| memcmp(header + 8, "AAVM", 4)) {
		fprintf(stderr, "Error: Bad or missing file header.\n");
		exit(1);
	}
	formsz = get32(header + 4);

	offset = 12;
	while(offset < 8 + formsz) {
		if(nchunk >= MAXCHUNK) {
			fprintf(stderr, "Error: Too many chunks in file.\n");
			exit(1);
		}
		if(8 != fread(header, 1, 8, f)) {
			fprintf(stderr, "Error reading chunk header at offset %08x.\n", offset);
			exit(1);
		}
		memcpy(chunk[nchunk].name, header, 4);
		chunk[nchunk].size = get32(header + 4);
		padded = (chunk[nchunk].size + 1) & ~1;
		chunk[nchunk].data = malloc(padded);
		if(padded != fread(chunk[nchunk].data, 1, padded, f)) {
			fprintf(stderr, "Error reading contents of chunk at offset %08x.\n", offset);
			exit(1);
		}
		offset += 8 + padded;
		nchunk++;
	}

	if(!nchunk || memcmp(chunk[0].name, "HEAD", 4)) {
		fprintf(stderr, "Error: First chunk must be HEAD.\n");
		exit(1);
	}

	if(chunk[0].data[0] != 0 || chunk[0].data[1] != 1) {
		fprintf(stderr, "Error: Unsupported aastory file format version (%d.%d)\n",
			chunk[0].data[0],
			chunk[0].data[1]);
		exit(1);
	}

	if(chunk[0].data[2] != 2) {
		fprintf(stderr, "Error: Unsupported word size (%d)\n",
			chunk[0].data[2]);
		exit(1);
	}

	strshift = chunk[0].data[3];

	ch = findchunk("LANG");
	if(ch) {
		extchars = ch->data + get16(ch->data + 2);
	} else {
		fprintf(stderr, "Error: No LANG chunk.\n");
		exit(1);
	}

	actual_crc = 0xffffffff;
	crc_chunk("LOOK");
	crc_chunk("LANG");
	crc_chunk("MAPS");
	crc_chunk("DICT");
	crc_chunk("INIT");
	crc_chunk("CODE");
	crc_chunk("WRIT");
	actual_crc ^= 0xffffffff;

	if(actual_crc != get32(chunk[0].data + 12)) {
		printf("Warning: CRC declared in header (%08x) does not match actual CRC (%08x).\n",
			get32(chunk[0].data + 12),
			actual_crc);
	}

	if(argc == 2) {
		list_chunks();
		printf("Total file size: %d bytes, %.1f kB\n", 8 + formsz, (8 + formsz) / 1024.0);
		printf("Add chunk name(s) to the end of the command line to explore further.\n");
	} else {
		for(i = 2; i < argc; i++) {
			if(i > 2) printf("\n");
			ch = findchunk(argv[i]);
			if(ch) {
				for(j = 0; decoder[j].func; j++) {
					if(!strcasecmp(argv[i], decoder[j].name)) {
						printf("=== %s ", decoder[j].name);
						for(k = 9; k < 79; k++) printf("=");
						printf("\n");
						decoder[j].func(ch);
						break;
					}
				}
				if(!decoder[j].func) {
					fprintf(stderr,
						"Error: Don't know how to decode chunk '%s'.\n",
						ch->name);
				}
			} else {
				fprintf(stderr, "Error: Failed to read chunk '%s'.\n", argv[i]);
			}
		}
	}

	fclose(f);
	return 0;
}
