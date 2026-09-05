VERSION=1.1.0
CFLAGS=-Wall -O2 -DVERSION=\"$(VERSION)\"

all:			aambox6502 aambox_frontend.bin c64_crunched.bin c64_drivecode.bin c64_loader.prg a2.system a2_0boot.bin a2_sboot.bin

check_xa:
	@if ! command -v xa >/dev/null 2>&1; then \
		echo "ERROR: 'xa' (6502 cross-assembler) not found in PATH."; \
		echo "  macOS:         brew install xa"; \
		echo "  Debian/Ubuntu: apt install xa65"; \
		echo "  From source:   https://www.floodgap.com/retrotech/xa/"; \
		exit 1; fi

check_acme:
	@if ! command -v acme >/dev/null 2>&1; then \
		echo "ERROR: 'acme' (6502 cross-assembler) not found in PATH."; \
		echo "  macOS:         brew install acme"; \
		echo "  Debian/Ubuntu: apt install acme"; \
		echo "  From source:   https://github.com/meonwax/acme"; \
		exit 1; fi

clean:
			rm -rf aambox6502 cruncher labels c64.labels mkfont
			rm -f a2_frontend.bin a2_prorwts2.bin a2.labels a2.system a2_0boot.bin a2_sboot.bin a2_sboot.labels

mkfont:			mkfont.c
			${CC} ${CFLAGS} -o $@ mkfont.c

cruncher:		cruncher.c
			${CC} ${CFLAGS} -o $@ cruncher.c

aambox6502:		aambox6502.c fake6502.c

aambox_frontend.bin:	aambox_frontend.s engine.s | check_xa
			xa -l aambox.labels -o $@ $< -DRAMTOP=49152

c64_frontend.bin:	c64_frontend.s engine.s font.bin | check_xa
			xa -l c64.labels -o $@ $< -DVERSION=\"$(VERSION)\"

font.bin:		fontdef.txt mkfont
			./mkfont <$< >$@

translit.s:		fontdef.txt mkfont
			./mkfont -t $@ <$<

c64_drivecode.bin:	c64_drivecode.s | check_xa
			xa -o $@ $<

c64_loader.prg:		c64_loader.s | check_xa
			xa -o $@ $<

decruncher.bin:		decruncher.s | check_xa
			xa -o $@ $<

c64_crunched.bin:	c64_frontend.bin decruncher.bin cruncher
			./cruncher $< decruncher.bin >$@

a2_0boot.bin:		a2_0boot.acme a2.system | check_acme
			acme -DA2_TRACKS=$$((($$(wc -c < a2.system) + 4095) / 4096)) -o $@ $<

a2_sboot.bin:		a2_sboot.s a2.system | check_xa
			xa -l a2_sboot.labels -o $@ $< -DAAM_BLOCKS=$$((($$(wc -c < a2.system) + 511) / 512))

a2_prorwts2.bin:	a2_prorwts2.acme a2_frontend.bin | check_acme
			acme -DPRORWTS_ORG=$$(($$(wc -c < a2_frontend.bin) + 8192)) -l a2_prorwts2.sym -r a2_prorwts2.rpt $<

a2_frontend.bin:	a2_frontend.s engine.s translit.s | check_xa
			xa -l a2.labels -P a2_frontend.lst -o $@ $< -DPRODOS=0 -DPRORWTS=1 -DVERSION=\"$(VERSION)\"

a2.system:		a2_frontend.bin a2_prorwts2.bin
			cat $^ > $@

.PHONY: all clean check_xa check_acme
