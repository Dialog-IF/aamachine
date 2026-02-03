# Call `make DIFF=meld`, for example, to get a fancy diff
DIFF = diff

all: test

test: gosling.out
	$(DIFF) gosling.out gosling.gold

gosling.out: gosling.aastory
	node ../../src/js/nodefrontend.js -s 1234 gosling.aastory <gosling.in >gosling.out

clean:
	rm -f *.out

.PHONY:		test clean
