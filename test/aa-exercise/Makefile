# The story source is aavm assembly (aa-exercise.scm).  Since the aavm
# assembler lives outside this repo, producing the .aastory is a separate
# `make assemble` step; `make test` (and the top-level test suite) does not
# include this directory.
ASSEMBLE = ../../../aavm/aavm.scm

include ../common.mk

assemble:
	$(ASSEMBLE) -S $(STORY).scm $(STORY).aastory

.PHONY: assemble