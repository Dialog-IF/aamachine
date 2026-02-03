test:
	make --directory=./test/gosling test clean
	make --directory=./test/impossible test clean

.PHONY: test
