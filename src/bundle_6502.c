#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include "aambundle.h"

// The aambox target: no packaging at all, just the rewritten .aastory.

void bundle_aambox(char *filename) {
	char storyname[256];

	visit_chunks(storyname, sizeof(storyname), 0);
	gen_usty_set_target("aambox");
	rewrite_chunks(rewrite_6502_sty, 1);
	writefile(NULL, filename, story, storysize);
}
