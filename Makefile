all: src/aamshow src/aambundle test

src/aamshow:
	$(MAKE) -C src

src/aambundle:
	$(MAKE) -C src

test: src/aamshow src/aambundle
	$(MAKE) -C test

install: src/aamshow src/aambundle
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

windows:
	$(MAKE) -C src windows

6502:
	$(MAKE) -C src 6502

.PHONY: all test clean tidy install uninstall distclean windows 6502
