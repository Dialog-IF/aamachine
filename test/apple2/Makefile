# Optional Apple II tests.
#
# These boot the 6502 interpreter from real disk images inside izapple2's
# scriptable console frontend (izconsole), driving it with the expect script
# a2test.exp.  Unlike the other test suites this one needs an
# external emulator, so it is not part of the default `make test`.
#
# If `make test` complains about a missing emulator, build and install it
# (https://github.com/ivanizag/izapple2):
#
#   git clone https://github.com/ivanizag/izapple2
#   cd izapple2
#   go build -o izconsole ./frontend/console
#   cp izconsole ~/bin/          # or anywhere on your PATH

# Autodetect: on PATH if installed there, otherwise ~/bin/izconsole.
# Override with: make IZCONSOLE=/path/to/izconsole
IZCONSOLE ?= $(shell command -v izconsole 2>/dev/null || echo "$$HOME/bin/izconsole")
# Extra izconsole flags for every test, e.g. a different Apple II model:
#   make test A2FLAGS="--model 2plus"
# a2test.exp reads this from the environment; see also the test.matrix target.
A2FLAGS ?=
# Make sure a2test.exp (run via expect) sees it too.
export IZCONSOLE
export A2FLAGS

DIR6502 = ../../src/6502
# Add --verbose to trace commands and dump the emulated screen on failure.
A2TEST = ./a2test.exp
AAMBUNDLE = ../../src/aambundle

AAEXERCISE_DIR = aa-exercise
AAEXERCISE_DSK = $(AAEXERCISE_DIR)/aa-exercise.dsk
GOSLING_DIR = gosling
GOSLING_PO = $(GOSLING_DIR)/Miss-Gosling-s-Last-Case-800k.po

all: test

# Undo snapshots live in auxiliary RAM, which only the 128 kB machines have.
# The 48 kB Apple ][+ reports undo as unavailable, so skip that one test for
# it rather than let it fail.
UNDO_TEST = test.undo
ifneq ($(findstring 2plus,$(A2FLAGS)),)
UNDO_TEST =
endif

test: check test.exercise test.gosling $(UNDO_TEST) test.save test.save2

# Run the whole suite once per emulated model.
# Individual models can also be run with: make test A2FLAGS="--model 2plus"
A2MODELS = 2e 2enh 2plus

test.matrix:
	@for m in $(A2MODELS); do \
	  echo "=== model $$m ==="; \
	  $(MAKE) test A2FLAGS="--model $$m" || exit 1; \
	done

# -- emulator and tool checks -------------------------------------------

check:
	@if [ ! -x "$(IZCONSOLE)" ]; then \
	  echo "*** izconsole not found (looked for $(IZCONSOLE))."; \
	  echo "*** The Apple II tests need the izapple2 console emulator."; \
	  echo "*** Build and install it:"; \
	  echo "***   git clone https://github.com/ivanizag/izapple2"; \
	  echo "***   cd izapple2 && go build -o izconsole ./frontend/console"; \
	  echo "***   cp izconsole $(HOME)/bin/    # or anywhere on your PATH"; \
	  exit 1; \
	fi
	@command -v expect >/dev/null 2>&1 || { \
	  echo "*** expect not found on PATH (needed by $(A2TEST))."; \
	  exit 1; \
	}

# -- the tests ------------------------------------------------------------
# Each target exits nonzero if the expected text never appears on the
# emulated screen (see a2test.exp for the exit code conventions).

test.exercise: $(AAEXERCISE_DSK)
	$(A2TEST) 250101 $(AAEXERCISE_DSK)

test.gosling: $(GOSLING_PO)
	$(A2TEST) 'Your work here is finished' $(GOSLING_PO) ../gosling/gosling.in

# Save/restore/undo tests. Each one boots the
# Gosling disk (which has a SAVEFILE), plays a few turns of the intro and
# then checks one metacommand:
#
#   test.undo  -- UNDO takes back a DROP, ball is back in Watson's mouth
#   test.save  -- SAVE, drop the ball, RESTORE: biting it must pop the treat
#                 out again, which is only possible with the restored state
#   test.save2 -- SAVE, drop the ball, RESTORE: INVENTORY must show the ball

test.undo: $(GOSLING_PO)
	$(A2TEST) 'Undoing the last turn' $(GOSLING_PO) gosling-undo.in

test.save: $(GOSLING_PO)
	$(A2TEST) 'pops out' $(GOSLING_PO) gosling-save.in

test.save2: $(GOSLING_PO)
	$(A2TEST) 'holds up the rubber ball proudly' $(GOSLING_PO) gosling-save2.in

# -- prerequisites --------------------------------------------------------

# The bundled disks live here too (gitignored), so the story directories
# stay clean.

$(AAMBUNDLE):
	$(MAKE) -C ../../src aambundle

$(AAEXERCISE_DSK): ../aa-exercise/aa-exercise.aastory $(AAMBUNDLE)
	$(AAMBUNDLE) -t apple2 -o $(AAEXERCISE_DIR) ../aa-exercise/aa-exercise.aastory

$(GOSLING_PO): ../gosling/gosling.aastory $(AAMBUNDLE)
	$(AAMBUNDLE) -t apple2 -o $(GOSLING_DIR) ../gosling/gosling.aastory

clean:
	@echo "Nothing to clean (the bundled disk images are .gitignored and left in place)."

.PHONY: all test test.matrix check test.exercise test.gosling test.undo test.save test.save2 clean
