#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
	int ch, x;

	if(argc != 2) {
		fprintf(stderr, "Usage: %s arrayname <input.bin >output.h", argv[0]);
		exit(1);
	}

	printf("uint8_t %s[] = {\n", argv[1]);
	x = 0;
	while((ch = fgetc(stdin)) != EOF) {
		if(!x++) printf("\t");
		printf("0x%02x,", ch);
		if(x == 16) {
			printf("\n");
			x = 0;
		}
	}
	if(x) printf("\n");
	printf("};\n");

	return 0;
}
