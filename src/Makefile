CC		= gcc
CFLAGS		+= -Wall -O3 -DVERSION=\"0.2.1\"
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

aambundle:		aambundle.c table_engine.h table_front.h table_jquery.h table_css.h table_play.h
			${CC} ${CFLAGS} -o $@ aambundle.c

aamshow.exe:		aamshow.c crc32.c aavm.c aavm.h crc32.h
			${MINGW32} ${CFLAGS} -o $@ aamshow.c crc32.c aavm.c

aambundle.exe:		aambundle.c table_engine.h table_front.h table_jquery.h table_css.h table_play.h
			${MINGW32} ${CFLAGS} -o $@ aambundle.c

table_engine.h:		js/engine.js mkheader
			./mkheader table_engine <$< >$@

table_front.h:		js/webfrontend.js mkheader
			./mkheader table_front <$< >$@

table_css.h:		js/webfrontend.css mkheader
			./mkheader table_css <$< >$@

table_play.h:		js/webfrontend.html mkheader
			./mkheader table_play <$< >$@

table_jquery.h:		js/jquery-3.4.1.min.js mkheader
			./mkheader table_jquery <$< >$@
