#include <unistd.h>
#include <sys/reboot.h>

int main() {
	setuid(0);
	reboot(RB_POWER_OFF);
	return 0;
}

// $ chown root:root panic
// $ chmod 4711 panic
