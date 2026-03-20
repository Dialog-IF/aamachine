DIALOGC=../../../Dialog/src/dialogc
AAMBUNDLE=../../src/aambundle

sourcefiles = familiar.dg world.dg interface.dg markov.dg soliloquy.dg nudge.dg automap.dg actions.dg
files = $(sourcefiles) stdlib.dg
outname = familiar

all: web

test: web

$(outname).aastory: $(files) hints.html
	$(DIALOGC) -vv -t aa -o familiar.aastory $(files)

web: $(outname).aastory
	rm -rf web
	$(AAMBUNDLE) -o web $(outname).aastory
	mv web/play.html web/index.html

clean:
	rm -rf web
	rm -f familiar.aastory

.PHONY: all web test clean
