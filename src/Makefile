VERSION=1.0.3
VER_MAJOR=1
VER_MINOR=0
CC		= gcc
CFLAGS		+= -Wall -O3 -DVERSION=\"$(VERSION)\" -DVER_MAJOR=$(VER_MAJOR) -DVER_MINOR=$(VER_MINOR)
ifeq ($(shell uname -s),Darwin)
CFLAGS		+= -arch x86_64 -arch arm64
endif
MINGW32		= i686-w64-mingw32-gcc
INSTALLDIR	= /usr/local/bin

# The C tools embed binary blobs produced by the 6502 sub-make (table_*.h).
# GNU make caches a file's timestamp before it runs a sub-make, so a single
# pass cannot tell whether the sub-make actually refreshed a blob.  Build the
# 6502 side first, then re-enter make: the second pass stats the blobs fresh
# and regenerates only the headers that really changed.
all: 6502
	$(MAKE) tools

6502:
	$(MAKE) -C 6502

tools: aamshow aambundle

windows: 6502
	$(MAKE) windows-tools

windows-tools: aamrun.exe aamshow.exe aambundle.exe

tidy:
	rm -f *.o

clean: tidy
	rm -f aamshow aambundle aamrun aamshow.exe aambundle.exe aamrun.exe
	$(MAKE) -C 6502 clean

install: all
	cp aamshow $(INSTALLDIR)
	cp aambundle $(INSTALLDIR)

install-aamrun: aamrun
	cp aamrun.linux $(INSTALLDIR)

uninstall:
	rm -f $(INSTALLDIR)/aamshow
	rm -f $(INSTALLDIR)/aambundle
	rm -f $(INSTALLDIR)/aamrun

distclean: clean uninstall

aamshow: aamshow.c crc32.c aavm.c aavm.h crc32.h
	${CC} ${CFLAGS} -o $@ aamshow.c crc32.c aavm.c

aambundle: aambundle.c bundle_web.c bundle_c64.c bundle_apple2.c \
	table_a2terp.h \
	table_a20boot.h \
	table_a2sboot.h \
	table_a2license.h \
	table_c64license.h \
	table_c64drive.h \
	table_c64load.h \
	table_c64terp.h \
	table_weblicense.h \
	table_css.h \
	table_engine.h \
	table_front.h \
	table_jquery.h \
	table_play.h \
	tables_6502font.h
	${CC} ${CFLAGS} -o $@ aambundle.c bundle_web.c bundle_c64.c bundle_apple2.c

aamrun.linux:	js/nodefrontend.js js/engine.js
	pkg -t linux -o aamrun.linux js/nodefrontend.js

aamrun.mac.x64:		js/nodefrontend.js js/engine.js
	pkg -t macos-x64   -o aamrun.mac.x64 js/nodefrontend.js

aamrun.mac.arm:		js/nodefrontend.js js/engine.js
	pkg -t macos-arm64 -o aamrun.mac.arm js/nodefrontend.js

aamrun.exe: js/nodefrontend.js js/engine.js
	pkg -t win -o aamrun.exe js/nodefrontend.js

aamshow.exe: aamshow.c crc32.c aavm.c aavm.h crc32.h
	${MINGW32} ${CFLAGS} -o $@ aamshow.c crc32.c aavm.c

aambundle.exe: aambundle.c bundle_web.c bundle_c64.c bundle_apple2.c \
	table_a2terp.h \
	table_a20boot.h \
	table_a2sboot.h \
	table_a2license.h \
	table_c64license.h \
	table_c64drive.h \
	table_c64load.h \
	table_c64terp.h \
	table_weblicense.h \
	table_css.h \
	table_engine.h \
	table_front.h \
	table_jquery.h \
	table_play.h \
	tables_6502font.h
	${MINGW32} ${CFLAGS} -o $@ aambundle.c bundle_web.c bundle_c64.c bundle_apple2.c

mkheader: mkheader.c
	${CC} ${CFLAGS} -o $@ mkheader.c

tables_6502font.h:	6502/fontdef.txt mkfontdata
			./mkfontdata <6502/fontdef.txt >tables_6502font.h

table_a2terp.h:		6502/a2.system mkheader
			./mkheader table_a2terp <6502/a2.system >$@

table_a20boot.h:	6502/a2_0boot.bin mkheader
			./mkheader table_a20boot <6502/a2_0boot.bin >$@

table_a2sboot.h:	6502/a2_sboot.bin mkheader
			./mkheader table_a2sboot <6502/a2_sboot.bin >$@

table_a2license.h:	6502/license.txt 6502/a2_thirdparty_license.txt mkheader
			cat 6502/license.txt 6502/a2_thirdparty_license.txt | ./mkheader table_a2license >$@

table_c64license.h:	6502/license.txt mkheader
			./mkheader table_c64license <6502/license.txt >$@

table_c64drive.h:	6502/c64_drivecode.bin mkheader
			./mkheader table_c64drive <6502/c64_drivecode.bin >$@

table_c64load.h:	6502/c64_loader.prg mkheader
			./mkheader table_c64load <6502/c64_loader.prg >$@

table_c64terp.h:	6502/c64_crunched.bin mkheader
			./mkheader table_c64terp <6502/c64_crunched.bin >$@

table_weblicense.h:	js/license.txt mkheader
			./mkheader table_weblicense <$< >$@

table_css.h:		js/webfrontend.css mkheader
			./mkheader table_css <$< >$@

table_engine.h:		js/engine.js mkheader
			./mkheader table_engine <$< >$@

table_front.h:		js/webfrontend.js mkheader
			./mkheader table_front <$< >$@

table_jquery.h:		js/jquery-3.4.1.min.js mkheader
			./mkheader table_jquery <$< >$@

table_play.h:		js/webfrontend.html mkheader
			./mkheader table_play <$< >$@

.PHONY:	all tools windows windows-tools clean tidy install uninstall distclean 6502
