VERSION=\"0.5.3\"
CFLAGS=-Wall -O2 -DVERSION=$(VERSION)

all:			aambox6502 aambox_frontend.bin c64_crunched.bin c64_drivecode.bin c64_loader.prg

aambox6502:		aambox6502.c fake6502.c

aambox_frontend.bin:	aambox_frontend.s engine.s
			xa -o $@ $<

c64_frontend.bin:	c64_frontend.s engine.s font.bin
			xa -l labels -o $@ $< -DVERSION=$(VERSION)

font.bin:		fontdef.txt mkfont
			./mkfont <$< >$@

c64_drivecode.bin:	c64_drivecode.s
			xa -o $@ $<

c64_loader.prg:		c64_loader.s
			xa -o $@ $<

decruncher.bin:		decruncher.s
			xa -o $@ $<

c64_crunched.bin:	c64_frontend.bin decruncher.bin cruncher
			./cruncher $< decruncher.bin >$@
