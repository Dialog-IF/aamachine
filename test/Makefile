## Tests:
##   gosling         - 0.x file using 67 ENTER_STATUS_0 and E7 LEAVE_STATUS
##   body_not_status - 1.x file using 67 BODY_STYLE and EF LEAVE_STATUS
##   impossible      - whatever the latest version of Dialog produces (update periodically)
##   codepoints      - Character set and status bar exercise; source is in the directory

TESTDIRS = gosling body_not_status impossible codepoints

TESTS  = $(addprefix test-,$(TESTDIRS))
CLEANS = $(addprefix clean-,$(TESTDIRS))

# Transcripts (.out files) are left in place so a second `make` only re-diffs;
# `make clean` (or deleting the .out files) forces a full re-run.
all: test

test: $(TESTS)

# Static pattern rules (not plain pattern rules): the targets are named
# explicitly, so they can be declared .PHONY without make refusing to apply
# the rule -- implicit-rule search is skipped for phony targets.
$(TESTS): test-%:
	$(MAKE) -C $* test

# Tests for Apple II interpreter (not run by make test)
apple2:
	$(MAKE) -C apple2 test

clean: $(CLEANS)

$(CLEANS): clean-%:
	$(MAKE) -C $* clean

.PHONY: all test apple2 clean $(TESTS) $(CLEANS)
