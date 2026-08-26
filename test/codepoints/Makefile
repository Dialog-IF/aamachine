# Call `make DIFF=meld` to get a fancy diff
DIFF = diff

DIR6502 = ../../src/6502
AAMBOX = $(DIR6502)/aambox6502
FRONTEND = $(DIR6502)/aambox_frontend.bin
AAMBUNDLE = ../../src/aambundle
DIALOGC ?= dialogc

$(AAMBOX):
	$(MAKE) -C $(DIR6502) aambox6502

$(FRONTEND):
	$(MAKE) -C $(DIR6502) aambox_frontend.bin

$(AAMBUNDLE):
	$(MAKE) -C ../../src aambundle

all: test

test: test.js test.6502

test.js: codepoints.js.out
	$(DIFF) codepoints.js.out codepoints.js.gold

codepoints.js.out: codepoints.aastory
	node ../../src/js/nodefrontend.js -s 1234 codepoints.aastory <codepoints.in >codepoints.js.out

test.6502: codepoints.6502.out
	$(DIFF) codepoints.6502.out codepoints.6502.gold

codepoints.6502.out: codepoints.aastory $(AAMBOX) $(FRONTEND)
	$(AAMBOX) -s 1234 $(FRONTEND) codepoints.aastory <codepoints.in >codepoints.6502.out

codepoints.aastory: codepoints.dg
	$(DIALOGC) -t aa -o $@ $<

# Neither the node frontend nor the aambox frontend renders a status area, and
# neither one transliterates -- both emit UTF-8 straight through.  So the two
# things this story actually exercises are invisible to `make test`, and have
# to be looked at on the real backends:
#
#   make disks && x64sc -truedrive codepoints/Codepoint-Exercise.d64
#   make disks && ~/bin/izconsole codepoints/Codepoint-Exercise.dsk
#
# Page 1-4  the transliteration table, one codepoint per line
# Page 5    the Z-machine fallback set in running text
# Page 6    line breaking: a run that breaks ends lines in 'aa', one that
#           holds ends every line in 'bb'
#	    (the runs exceed 80 columns, so `make test` exercises them at
#	     the automated backends' width too; real hardware adds nothing
#	     for this page but is still needed for pages 1-5 and 7)
# Page 7    negative control, every line should be the unknown-char glyph
# Page 10   [MORE] accounting across a line-input prompt.  The window is filled
#           to exactly one line short of the pagination limit and then a line
#           of input is read. Pressing RETURN there must not raise [MORE], and
#           neither may the (clear all) that follows it.
#           (Use +/- to nudge the status bar height for 24/25 row systems.)

disks: codepoints.aastory $(AAMBUNDLE)
	$(AAMBUNDLE) -t apple2 -o codepoints codepoints.aastory
	$(AAMBUNDLE) -t c64 -o codepoints codepoints.aastory

clean:
	rm -f *.out

.PHONY: all test test.js test.6502 disks clean
