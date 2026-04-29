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

test.js: body_not_status.js.out
	$(DIFF) body_not_status.js.out body_not_status.gold

body_not_status.js.out: body_not_status.aastory
	node ../../src/js/nodefrontend.js -s 1234 body_not_status.aastory <body_not_status.in >body_not_status.js.out

test.6502: body_not_status.6502.out
	$(DIFF) body_not_status.6502.out body_not_status.gold

body_not_status.6502.out: body_not_status.aastory $(AAMBOX) $(FRONTEND)
	$(AAMBOX) -s 1234 $(FRONTEND) body_not_status.aastory <body_not_status.in >body_not_status.6502.out

clean:
	rm -f *.out

.PHONY:		all test test.js test.6502 clean
