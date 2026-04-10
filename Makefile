BINARIES=src/aamshow src/aambundle

all: $(BINARIES) 6502 test

src/aamshow:
	$(MAKE) -C src

src/aambundle:
	$(MAKE) -C src

windows:
	$(MAKE) -C src windows

6502:
	$(MAKE) -C src 6502

no6502: $(BINARIES) test

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

.PHONY: all test clean tidy install uninstall distclean windows 6502 no6502
