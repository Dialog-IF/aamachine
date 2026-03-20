all: test clean

test:
	$(MAKE) -C gosling test
	$(MAKE) -C impossible test
	$(MAKE) -C familiar test

clean:
	$(MAKE) -C gosling clean
	$(MAKE) -C impossible clean
	$(MAKE) -C familiar clean

.PHONY: all test clean
