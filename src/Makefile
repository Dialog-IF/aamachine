CC		= gcc
CFLAGS		+= -Wall -O3 -DVERSION=\"0.4.3\"
MINGW32		= i686-w64-mingw32-gcc

all:			aamshow aambundle

clean:
			rm -f aamshow aambundle aamshow.exe aambundle.exe *.o

install:		aamshow aambundle
			cp aamshow /usr/local/bin/
			cp aambundle /usr/local/bin/

.PHONY:			all clean install

aamshow:		aamshow.c crc32.c aavm.c aavm.h crc32.h
			${CC} ${CFLAGS} -o $@ aamshow.c crc32.c aavm.c

aambundle:		aambundle.c bundle_web.c bundle_c64.c \
				table_c64drive.h \
				table_c64load.h \
				table_c64terp.h \
				table_css.h \
				table_engine.h \
				table_front.h \
				table_jquery.h \
				table_play.h
			${CC} ${CFLAGS} -o $@ aambundle.c bundle_web.c bundle_c64.c

aamshow.exe:		aamshow.c crc32.c aavm.c aavm.h crc32.h
			${MINGW32} ${CFLAGS} -o $@ aamshow.c crc32.c aavm.c

aambundle.exe:		aambundle.c bundle_web.c bundle_c64.c \
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
