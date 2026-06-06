# Call `make DIFF=meld` to get a fancy diff
DIFF = diff

DIR6502 = ../../src/6502
AAMBOX = $(DIR6502)/aambox6502
FRONTEND = $(DIR6502)/aambox_frontend.bin
ASSEMBLE = ../../../aavm/aavm.scm

$(AAMBOX):
	$(MAKE) -C $(DIR6502) aambox6502

$(FRONTEND):
	$(MAKE) -C $(DIR6502) aambox_frontend.bin

assemble:
	$(ASSEMBLE) -S aa-exercise.scm aa-exercise.aastory

all: test

test: test.js test.6502

test.js: aa-exercise.js.out
	$(DIFF) aa-exercise.js.out aa-exercise.js.gold

aa-exercise.js.out: aa-exercise.aastory
	node ../../src/js/nodefrontend.js -s 1234 aa-exercise.aastory <aa-exercise.in >aa-exercise.js.out

test.6502: aa-exercise.6502.out
	$(DIFF) aa-exercise.6502.out aa-exercise.6502.gold

aa-exercise.6502.out: aa-exercise.aastory $(AAMBOX) $(FRONTEND)
	$(AAMBOX) -s 1234 $(FRONTEND) aa-exercise.aastory <aa-exercise.in >aa-exercise.6502.out

clean:
	rm -f *.out

.PHONY: all test test.js test.6502 clean
