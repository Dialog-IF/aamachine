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

all: aamshow aambundle

windows: aamrun.exe aamshow.exe aambundle.exe

6502:
	$(MAKE) -C 6502

tidy:
	rm -f *.o

clean: tidy
	rm -f aamshow aambundle aamrun aamshow.exe aambundle.exe aamrun.exe
	$(MAKE) -C 6502 clean

install: aamshow aambundle
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

aambundle: aambundle.c bundle_web.c bundle_c64.c \
	table_c64license.h \
	table_c64drive.h \
	table_c64load.h \
	table_c64terp.h \
	table_weblicense.h \
	table_css.h \
	table_engine.h \
	table_front.h \
	table_jquery.h \
	table_play.h
	${CC} ${CFLAGS} -o $@ aambundle.c bundle_web.c bundle_c64.c

aamrun.linux:	js/nodefrontend.js js/engine.js
	pkg -t linux -o aamrun.linux js/nodefrontend.js

aamrun.mac:		js/nodefrontend.js js/engine.js
	pkg -t macos-x64   -o aamrun.mac.x64   js/nodefrontend.js
	pkg -t macos-arm64 -o aamrun.mac.arm64 js/nodefrontend.js
	lipo -create -output aamrun.mac aamrun.mac.x64 aamrun.mac.arm64
	rm -f aamrun.mac.x64 aamrun.mac.arm64

aamrun.exe: js/nodefrontend.js js/engine.js
	pkg -t win -o aamrun.exe js/nodefrontend.js

aamshow.exe: aamshow.c crc32.c aavm.c aavm.h crc32.h
	${MINGW32} ${CFLAGS} -o $@ aamshow.c crc32.c aavm.c

aambundle.exe: aambundle.c bundle_web.c bundle_c64.c \
	table_c64license.h \
	table_c64drive.h \
	table_c64load.h \
	table_c64terp.h \
	table_weblicense.h \
	table_css.h \
	table_engine.h \
	table_front.h \
	table_jquery.h \
	table_play.h
	${MINGW32} ${CFLAGS} -o $@ aambundle.c bundle_web.c bundle_c64.c

table_c64license.h:	6502 6502/license.txt mkheader
			./mkheader table_c64license <6502/license.txt >$@

table_c64drive.h:	6502 6502/c64_drivecode.bin mkheader
			./mkheader table_c64drive <6502/c64_drivecode.bin >$@

table_c64load.h:	6502 6502/c64_loader.prg mkheader
			./mkheader table_c64load <6502/c64_loader.prg >$@

table_c64terp.h:	6502 6502/c64_crunched.bin mkheader
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

.PHONY:	all clean tidy install uninstall distclean windows 6502
