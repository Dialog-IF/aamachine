BINARIES=src/aamshow src/aambundle

all: $(BINARIES) test

src/aamshow:
	$(MAKE) -C src

src/aambundle:
	$(MAKE) -C src

test: $(BINARIES)
	$(MAKE) -C test

install: $(BINARIES)
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
	$(MAKE) -C src/6502 all

.PHONY: all test clean tidy install uninstall distclean windows 6502
