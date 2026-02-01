sourcefiles = familiar.dg world.dg interface.dg markov.dg soliloquy.dg nudge.dg automap.dg actions.dg
files = $(sourcefiles) stdlib.dg
outname = familiar

all: web

$(outname).aastory: $(files) hints.html
	../../../Dialog/src/dialogc -vv -t aa -o familiar.aastory $(files)

web: $(outname).aastory
	rm -rf web
	../../src/aambundle -o web $(outname).aastory
	mv web/play.html web/index.html

clean:
	rm -rf web
	rm familiar.aastory
