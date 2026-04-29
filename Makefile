# Generate all binaries
all:
	make --directory=./src/6502 all
	make --directory=./src all

test:
	## Ensure no compilation failures
	make --directory=./src/6502 all clean
	make --directory=./src all clean
	## Run the actual test cases
	## This one is a 0.x file using $67 ENTER_STATUS_0 and $e7 LEAVE_STATUS
	make --directory=./test/gosling test clean
	## This one is a 1.x file using $67 BODY_STYLE and $ef LEAVE_STATUS
	make --directory=./test/body_not_status test clean
	## This one is whatever the latest version of Dialog produces (update periodically)
	make --directory=./test/impossible test clean

.PHONY: test all
