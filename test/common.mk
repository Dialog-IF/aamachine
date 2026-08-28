# Shared rules for the simple JS-vs-6502 comparison test suites.
#
# Each suite lives in a directory named after its story, and holds
# STORY.aastory (or a rule to build it), STORY.in, and transcript gold
# files.  A suite's Makefile usually needs only:
#
#     include ../common.mk
#
# Everything is driven by a few variables, all with sensible defaults:
#
#   STORY     basename of the story files; defaults to the directory name
#   JS_GOLD   gold transcript for the JS engine
#   GOLD6502  gold transcript for the 6502 engine
#   DIFF      diff program, e.g. `make DIFF=meld`  (see below)
#
# Most suites keep separate JS and 6502 golds; suites where the two engines
# must produce identical output (body_not_status, impossible) point both
# variables at one file.
#
# Suites that need extra targets (aavm assembly, disk bundling, ...) simply
# add their own rules after the include, and extend .PHONY accordingly.

# Call `make DIFF=meld` to get a fancy diff
DIFF ?= diff

STORY ?= $(notdir $(CURDIR))
JS_GOLD ?= $(STORY).js.gold
GOLD6502 ?= $(STORY).6502.gold

DIR6502 = ../../src/6502
AAMBOX = $(DIR6502)/aambox6502
AAMFRONTEND = $(DIR6502)/aambox_frontend.bin
AAMBUNDLE = ../../src/aambundle

JS_ENGINE = ../../src/js/engine.js
JS_FRONTEND = ../../src/js/nodefrontend.js

# Build the 6502 engine pieces if they are not already built.
$(AAMBOX): $(DIR6502)/aambox6502.c $(DIR6502)/fake6502.c
	$(MAKE) -C $(DIR6502) aambox6502

$(AAMFRONTEND): $(DIR6502)/aambox_frontend.s $(DIR6502)/engine.s
	$(MAKE) -C $(DIR6502) aambox_frontend.bin

$(AAMBUNDLE):
	$(MAKE) -C ../src aambundle

all: test

test: test.js test.6502

# Run the story on the JS engine and diff the transcript.
test.js: $(STORY).js.out
	$(DIFF) $(STORY).js.out $(JS_GOLD)

$(STORY).js.out: $(STORY).aastory $(STORY).in $(JS_ENGINE) $(JS_FRONTEND)
	node $(JS_FRONTEND) -s 1234 $< <$(STORY).in >$@

# Run the story on the 6502 engine (under the aambox emulator) and diff.
test.6502: $(STORY).6502.out
	$(DIFF) $(STORY).6502.out $(GOLD6502)

$(STORY).6502.out: $(STORY).ustory $(STORY).in $(AAMBOX) $(AAMFRONTEND)
	$(AAMBOX) -s 1234 $(AAMFRONTEND) $< <$(STORY).in >$@

# Convert .aastory to .ustory to add USTY chunk
$(STORY).ustory: $(STORY).aastory $(AAMBUNDLE)
	$(AAMBUNDLE) -t aambox --no-warn-style -o $@ $<

clean:
	rm -f *.out

.PHONY: all test test.js test.6502 clean
