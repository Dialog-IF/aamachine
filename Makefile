test:
	## Ensure no compilation failures
	make --directory=./src/6502 all clean
	make --directory=./src all clean
	## Run the actual test cases
	make --directory=./test/gosling test clean
	make --directory=./test/impossible test clean

.PHONY: test
