#include <stdio.h>

#define BRIGHT "/sys/class/backlight/pwm-backlight.0/brightness"
#define MAX 2800
#define MIN 1
#define INC 280

int getCurrent() {
	int cur;
	FILE *bFile = fopen(BRIGHT, "r");
        fscanf(bFile,"%i", &cur);
        fclose(bFile);
	return cur;
}

void writeNew(int new) {
	FILE *bFile = fopen(BRIGHT,"w");
        fprintf(bFile, "%i", new);
        fclose(bFile);
}

int main(int argc, char *argv[]) {
	char dir = *argv[1];
	if(argc != 2) {
		printf("Please specify +/-\n");
		return 1;
	}
	int inc = INC;
	if(dir == '-') {
		inc = -1*inc;
	}
	int current = getCurrent();
	int new = current + inc;
	if(new > MAX) {
		new = MAX;
	} else if(new < MIN) {
		new = MIN;
	}
	writeNew(new);
	return 0;
}
