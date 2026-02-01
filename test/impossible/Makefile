# Call `make DIFF=meld`, for example, to get a fancy diff
DIFF = diff

all: test

test: impossible.out
	$(DIFF) impossible.out impossible.gold

impossible.out: impossible.aastory
	node ../../src/js/nodefrontend.js -s 1234 impossible.aastory <impossible.in >impossible.out

clean:
	rm -f *.out

.PHONY:		test clean
