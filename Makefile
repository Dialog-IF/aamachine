# Full build: the 6502 blobs, then the C tools that embed them, then the tests.
all: tools test

# "make -C src" builds the 6502 side first, then the C tools.
tools:
	$(MAKE) -C src

# Only the 6502 engine, frontends, and the aambox6502 emulator.
6502:
	$(MAKE) -C src 6502

windows:
	$(MAKE) -C src windows

test: tools
	$(MAKE) -C test

install: tools
	$(MAKE) -C src install

tidy:
	$(MAKE) -C src tidy
	$(MAKE) -C test clean

clean:
	$(MAKE) -C src clean
	$(MAKE) -C test clean

uninstall:
	$(MAKE) -C src uninstall

distclean: clean uninstall

.PHONY: all tools windows 6502 test clean tidy install uninstall distclean
