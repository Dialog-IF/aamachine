# Call `make DIFF=meld` to get a fancy diff
DIFF = diff

DIR6502 = ../../src/6502
AAMBOX = $(DIR6502)/aambox6502
FRONTEND = $(DIR6502)/aambox_frontend.bin

$(AAMBOX):
	$(MAKE) -C $(DIR6502) aambox6502

$(FRONTEND):
	$(MAKE) -C $(DIR6502) aambox_frontend.bin

all: test

test: test.js test.6502

test.js: gosling.js.out
	$(DIFF) gosling.js.out gosling.js.gold

gosling.js.out: gosling.aastory
	node ../../src/js/nodefrontend.js -s 1234 gosling.aastory <gosling.in >gosling.js.out

test.6502: gosling.6502.out
	$(DIFF) gosling.6502.out gosling.6502.gold

gosling.6502.out: gosling.aastory $(AAMBOX)
	$(AAMBOX) -s 1234 $(FRONTEND) gosling.aastory <gosling.in >gosling.6502.out

clean:
	rm -f *.out

.PHONY:		all test test.js test.6502 clean
