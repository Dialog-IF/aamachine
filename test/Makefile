all: test clean

test:
	## This one is a 0.x file using 67 ENTER_STATUS_0 and E7 LEAVE_STATUS
	make -C gosling test
	## This one is a 1.x file using 67 BODY_STYLE and EF LEAVE_STATUS
	make -C body_not_status test
	## This one is whatever the latest version of Dialog produces (update periodically)
	make -C impossible test

clean:
	$(MAKE) -C gosling clean
	$(MAKE) -C body_not_status clean
	$(MAKE) -C impossible clean

.PHONY: all test clean
