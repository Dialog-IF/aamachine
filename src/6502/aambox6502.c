/* This file is part of the Aa-machine 6502 engine by Linus Akesson. */

#include <errno.h>
#include <getopt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define SAVEFILE "aambox.aasave"

#define MAXUNDO 50

// These are zero-page variables in the engine:
#define FIRSTPG 0x7e
#define ENDPG 0x7f

/* We use the "fake6502" CPU emulator by Mike Chambers. */
void reset6502();
void exec6502(uint32_t tickcount);
void step6502();
extern uint16_t pc;

/*
	This is a very simple 6502-based machine with a special set of
	registers for terminal I/O and loading from an external ROM.

	Memory map:

	0000-00ff rw	RAM (zero-page)
	0100-01ff rw	RAM (stack)

	0200 w		Send a character to stdout
	0201 r		Read a character from stdin (freezes the machine)
	0202 w		Quit

	0210 w		External ROM address 15:8
	0211 w		External ROM address 23:16
	0212 w		Target RAM address 15:8
	0213 w		Trigger a full page read

	0220 w		Log hex value
	0221 w		Log linefeed
	0222 w		Log space

	0230 w		Prepare next random number
	0231 r		Random number LSB
	0232 r		Random number MSB

	0240 w		Undo data pointer LSB
	0241 w		Undo data pointer MSB
	0242 w		Undo data size LSB
	0243 w		Undo data size MSB
	0244 w		Trigger undo push
	0245 w		Trigger undo pop
	0246 r		Post-pop status: 0 = ok, 1 = no more, 2 = error
	0247 w		Clear undo buffers

	0250 w		Savefile address LSB
	0251 w		Savefile address MSB
	0252 w		Savefile size LSB
	0253 w		Savefile size MSB
	0254 w		Trigger save (from savefile address, of given size)
	0255 w		Trigger load (to savefile address)
	0256 r		1 if previous load was successful, 0 otherwise

	0300-ffff rw	RAM (preloaded with program)

	The reset vector (in RAM) is initialized to 0300.
*/

uint8_t core[0x10000];
uint8_t *extrom;
int nallocext;
int extromsize;

uint8_t *undotbl[MAXUNDO];
int nundo;
int did_cull_undo;

uint8_t diskmark;
int diskdelay;

uint32_t lastextaddr = ~0;

uint16_t cycles;
int32_t randomseed = 1;
int report_cycles;

FILE *pagelog;

void quit() {
	if(report_cycles) {
		printf("%lld cycles", (long long) cycles);
	}
	printf("\n");
	if(pagelog) {
		fclose(pagelog);
	}
	exit(0);
}

uint8_t read6502(uint16_t address) {
	int ch;

	cycles++;

	if(address == 0x0201) {
		fflush(stdout);
		ch = fgetc(stdin);
		if(ch == EOF) quit();
		fputc(ch, stdout);
		return ch;
	} else {
		return core[address];
	}
}

void write6502(uint16_t address, uint8_t value) {
	uint32_t extaddr;
	uint16_t intaddr;
	uint16_t size;
	uint8_t header[12];
	FILE *f;

	cycles++;

	if(address >= (core[FIRSTPG] << 8) && address < (core[ENDPG] << 8)) {
		fprintf(stderr, "Write inside page area %04x, first %02x, end %02x, pc = %04x\n",
			address,
			core[FIRSTPG],
			core[ENDPG],
			pc);
		exit(1);
	}

	core[address] = value;

	if((address & 0xff00) == 0x0200) {
		switch(address) {
		case 0x0200:
			fputc(value, stdout);
			break;
		case 0x0202:
			quit();
			break;
		case 0x0213:
			extaddr =
				(core[0x0210] << 8) |
				(core[0x0211] << 16);
			intaddr =
				(core[0x0212] << 8);
			if(extaddr >= extromsize) {
				fprintf(stderr, "Attempting to read external rom at %06x\n", extaddr);
				exit(1);
			}
			if(intaddr < (core[FIRSTPG] << 8) || intaddr >= (core[ENDPG] << 8)) {
				fprintf(stderr, "Attempting to page into %04x, first %02x, end %02x\n",
					intaddr,
					core[FIRSTPG],
					core[ENDPG]);
				exit(1);
			}
			if(pagelog) {
				fwrite(core + 0x0210, 2, 1, pagelog);
			}
			memcpy(core + intaddr, extrom + extaddr, 256);
			cycles += 256;
			if(diskmark) {
				if(extaddr == lastextaddr + 0x100) {
					printf("~");
				} else {
					printf("#");
				}
			}
			if(diskdelay) {
				fflush(stdout);
				usleep(diskdelay * 1000);
			}
			lastextaddr = extaddr;
			break;
		case 0x0220:
			printf("%02x", value);
			break;
		case 0x0221:
			printf("\n");
			break;
		case 0x0222:
			printf(" ");
			break;
		case 0x0230:
			randomseed = 0x15a4e35L * randomseed + 1;
			core[0x0231] = (randomseed >> 16) & 0xff;
			core[0x0232] = (randomseed >> 24) & 0x7f;
			break;
		case 0x0244:
			if(nundo >= MAXUNDO) {
				free(undotbl[0]);
				memmove(undotbl, undotbl + 1, (MAXUNDO - 1) * sizeof(uint8_t *));
				did_cull_undo = 1;
			} else {
				nundo++;
			}
			intaddr = core[0x0240] | (core[0x0241] << 8);
			size = core[0x0242] | (core[0x0243] << 8);
			undotbl[nundo - 1] = malloc(size);
			memcpy(undotbl[nundo - 1], core + intaddr, size);
			cycles += size;
			break;
		case 0x0245:
			if(nundo) {
				intaddr = core[0x0240] | (core[0x0241] << 8);
				size = core[0x0242] | (core[0x0243] << 8);
				memcpy(core + intaddr, undotbl[--nundo], size);
				cycles += size;
				free(undotbl[nundo]);
				core[0x0246] = 0;
			} else {
				core[0x0246] = 1 + did_cull_undo;
			}
			break;
		case 0x0247:
			while(nundo) {
				free(undotbl[--nundo]);
			}
			did_cull_undo = 0;
			randomseed = 4242;
			break;
		case 0x0254:
			f = fopen(SAVEFILE, "wb");
			if(f) {
				intaddr = core[0x0250] | (core[0x0251] << 8);
				size = core[0x0252] | (core[0x0253] << 8);
				fwrite(core + intaddr, 1, size, f);
				fclose(f);
			} else {
				fprintf(stderr, "%s: %s\n", SAVEFILE, strerror(errno));
			}
			break;
		case 0x0255:
			core[0x0256] = 0;
			f = fopen(SAVEFILE, "rb");
			if(f) {
				if(12 != fread(header, 1, 12, f)
				|| header[0] != 'F'
				|| header[1] != 'O'
				|| header[2] != 'R'
				|| header[3] != 'M'
				|| header[8] != 'A'
				|| header[9] != 'A'
				|| header[10] != 'S'
				|| header[11] != 'V') {
					fprintf(stderr, "%s: Header-check failed\n", SAVEFILE);
				} else {
					fseek(f, 0, SEEK_SET);
					intaddr = core[0x0250] | (core[0x0251] << 8);
					fread(core + intaddr, 1, 0x10000 - intaddr, f);
					core[0x0256] = 1;
				}
			} else {
				fprintf(stderr, "%s: %s\n", SAVEFILE, strerror(errno));
			}
			break;
		}
	}
#if 0
	if(address >= 0x300) {
		printf("write %02x -> %04x\n", value, address);
	}
#endif
}

void usage(char *prgname) {
	fprintf(stderr, "Aa-machine tools " VERSION "\n");
	fprintf(stderr, "Copyright 2019-2022 Linus Akesson.\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "Usage: %s [options] frontend.bin externalrom.aastory\n", prgname);
	fprintf(stderr, "\n");
	fprintf(stderr, "Options:\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "--version    -V    Display the program version.\n");
	fprintf(stderr, "--help       -h    Display this information.\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "--seed       -s    Specify random seed.\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "--disk-delay -d    Set simulated loading delay in milliseconds.\n");
	fprintf(stderr, "--disk-marks -m    Enable inline characters to visualize loading.\n");
	fprintf(stderr, "--page-log   -p    Specify a file for logging page numbers.\n");
	fprintf(stderr, "--cycles     -c    Report number of cycles spent.\n");
	exit(1);
}

int main(int argc, char **argv) {
	struct option longopts[] = {
		{"help", 0, 0, 'h'},
		{"version", 0, 0, 'V'},
		{"seed", 1, 0, 's'},
		{"disk-delay", 1, 0, 'd'},
		{"disk-marks", 0, 0, 'm'},
		{"page-log", 1, 0, 'p'},
		{0, 0, 0, 0}
	};
	char *prgname = argv[0];
	FILE *f;
	size_t sz;
	int opt;
	char *pagelogname = 0;

	do {
		opt = getopt_long(argc, argv, "?hVs:d:mp:c", longopts, 0);
		switch(opt) {
			case 0:
			case '?':
			case 'h':
				usage(prgname);
				break;
			case 'V':
				fprintf(stderr, "Aa-machine tools " VERSION "\n");
				exit(0);
			case 's':
				randomseed = strtol(optarg, 0, 10);
				break;
			case 'p':
				pagelogname = strdup(optarg);
				break;
			case 'm':
				diskmark = 1;
				break;
			case 'd':
				diskdelay = atoi(optarg);
				break;
			case 'c':
				report_cycles = 1;
				break;
			default:
				if(opt >= 0) {
					fprintf(stderr, "Unimplemented option '%c'\n", opt);
					exit(1);
				}
				break;
		}
	} while(opt >= 0);

	argc -= optind;
	argv += optind;

	if(argc != 2) {
		usage(prgname);
	}

	f = fopen(argv[0], "rb");
	if(!f) {
		fprintf(stderr, "%s: %s\n", argv[0], strerror(errno));
		exit(1);
	}
	fread(core + 0x0300, 1, sizeof(core) - 0x0300, f);
	fclose(f);

	f = fopen(argv[1], "rb");
	if(!f) {
		fprintf(stderr, "%s: %s\n", argv[1], strerror(errno));
		exit(1);
	}
	do {
		nallocext += 65536;
		extrom = realloc(extrom, nallocext);
		sz = fread(extrom + extromsize, 1, 65536, f);
		extromsize += sz;
	} while(sz == 65536);
	fclose(f);

	if(pagelogname) {
		pagelog = fopen(pagelogname, "wb");
		if(!pagelog) {
			fprintf(stderr, "%s: %s\n", pagelogname, strerror(errno));
		}
	}

	core[0xfffc] = 0x00;
	core[0xfffd] = 0x03;

	reset6502();
	for(;;) {
		step6502();
	}
}
