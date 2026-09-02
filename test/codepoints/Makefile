# The story is compiled from Dialog source with an external compiler.
DIALOGC ?= dialogc
AAMBUNDLE = ../../src/aambundle

include ../common.mk

# Neither the node frontend nor the aambox frontend renders a status area, and
# neither one transliterates -- both emit UTF-8 straight through.  So the two
# things this story actually exercises are invisible to `make test`, and have
# to be looked at on the real backends:
#
#   make disks && x64sc -truedrive codepoints/Codepoint-Exercise.d64
#   make disks && ~/bin/izconsole codepoints/Codepoint-Exercise.dsk
#
# Page 1-6  the transliteration table, one codepoint per line.  Generated
#           from src/6502/fontdef.txt -- every codepoint with a translit
#           there appears exactly once here, and pages 9 and 11 must hold
#           none of them
# Page 7    the Z-machine fallback set in running text
# Page 8    line breaking: a run that breaks ends lines in 'aa', one that
#           holds ends every line in 'bb'
#	    (the runs exceed 80 columns, so `make test` exercises them at
#	     the automated backends' width too; real hardware adds nothing
#	     for this page but is still needed for pages 1-7 and 9)
# Page 9    negative control, every line should be the unknown-char glyph
# Page 12   [MORE] accounting across a line-input prompt.  The window is filled
#           to exactly one line short of the pagination limit and then a line
#           of input is read. Pressing RETURN there must not raise [MORE], and
#           neither may the (clear all) that follows it.
#           (Use +/- to nudge the status bar height for 24/25 row systems.)

$(STORY).aastory: $(STORY).dg
	$(DIALOGC) -t aa -o $@ $<

$(AAMBUNDLE):
	$(MAKE) -C ../../src aambundle

disks: $(STORY).aastory $(AAMBUNDLE)
	$(AAMBUNDLE) -t apple2 -o $(STORY) $(STORY).aastory
	$(AAMBUNDLE) -t c64 -o $(STORY) $(STORY).aastory

.PHONY: disks