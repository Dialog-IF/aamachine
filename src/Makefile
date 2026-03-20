VERSION=\"1.0.0\"
VER_MAJOR=1
VER_MINOR=0
CC		= gcc
CFLAGS		+= -Wall -O3 -DVERSION=$(VERSION) -DVER_MAJOR=$(VER_MAJOR) -DVER_MINOR=$(VER_MINOR)
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
	cp aamrun $(INSTALLDIR)

uninstall:
	rm -f $(INSTALLDIR)/aamshow
	rm -f $(INSTALLDIR)/aambundle
	rm -f $(INSTALLDIR)/aamrun

distclean: clean uninstall

aamrun: js/nodefrontend.js js/engine.js
	pkg -t linux -o aamrun js/nodefrontend.js

aamshow: aamshow.c crc32.c aavm.c aavm.h crc32.h
	${CC} ${CFLAGS} -o $@ aamshow.c crc32.c aavm.c

aambundle: aambundle.c bundle_web.c bundle_c64.c \
	table_c64drive.h \
	table_c64load.h \
	table_c64terp.h \
	table_css.h \
	table_engine.h \
	table_front.h \
	table_jquery.h \
	table_play.h
	${CC} ${CFLAGS} -o $@ aambundle.c bundle_web.c bundle_c64.c

aamrun.exe: js/nodefrontend.js js/engine.js
	pkg -t win -o aamrun.exe js/nodefrontend.js

aamshow.exe: aamshow.c crc32.c aavm.c aavm.h crc32.h
	${MINGW32} ${CFLAGS} -o $@ aamshow.c crc32.c aavm.c

aambundle.exe: aambundle.c bundle_web.c bundle_c64.c \
	table_c64drive.h \
	table_c64load.h \
	table_c64terp.h \
	table_css.h \
	table_engine.h \
	table_front.h \
	table_jquery.h \
	table_play.h
	${MINGW32} ${CFLAGS} -o $@ aambundle.c bundle_web.c bundle_c64.c

table_c64drive.h:	6502/c64_drivecode.bin mkheader
			./mkheader table_c64drive <$< >$@

table_c64load.h:	6502/c64_loader.prg mkheader
			./mkheader table_c64load <$< >$@

table_c64terp.h:	6502/c64_crunched.bin mkheader
			./mkheader table_c64terp <$< >$@

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
