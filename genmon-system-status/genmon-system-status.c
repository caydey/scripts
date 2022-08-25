#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/statvfs.h>

// ---- config ----
// 'current' meaning voltage divided by resistance
const char *CURRENT_DEVICE = "/sys/class/power_supply/BAT1/current_now";

const int TEMPERATURE_DEVICES_COUNT = 3;
const char *TEMPERATURE_DEVICES[] = {
  "/sys/class/thermal/thermal_zone0/temp",
  "/sys/class/thermal/thermal_zone1/temp",
  "/sys/class/thermal/thermal_zone2/temp"
};

const int DISK_DEVICES_COUNT = 3;
const char *DISK_DEVICES[] = {
  "/",
  "/home",
  "/data"
};

// ---- config ----


const unsigned int MB = 1024 * 1024;
const unsigned int GB = MB * 1024;

FILE *fp;

typedef struct system_memory {
  float memory;
  float memory_total;
  float swap;
  float swap_total;
} System_memory;

typedef struct temperature {
  int temperatures[9]; // """large""" number
  int max_temperature;
} Temperature;

typedef struct disk_stats {
  float used;
  float total;
} Disk_stats;

float get_current() {
  int int_buff = 0;
  fp = fopen(CURRENT_DEVICE, "r");
  if (fp != NULL) {
    fscanf(fp, "%d", &int_buff);
    fclose(fp);
  }

  float current = int_buff / 1000000.0;
  return current;
}

Temperature get_temperature() {
  Temperature temperature;
  temperature.max_temperature = 0;
  for (int i = 0; i < TEMPERATURE_DEVICES_COUNT; i++) {
    fp = fopen(TEMPERATURE_DEVICES[i], "r");
    if (fp != NULL) {
      fscanf(fp, "%d", &temperature.temperatures[i]);
      fclose(fp);
      temperature.temperatures[i] /= 1000;
      if (temperature.max_temperature < temperature.temperatures[i]) {
        temperature.max_temperature = temperature.temperatures[i];
      }
    }
  }

  return temperature;
}

Disk_stats get_disk_stats(const char *path) {
  struct statvfs buffer;
  statvfs(path, &buffer);

  const float total = (float)(buffer.f_blocks * buffer.f_frsize) / GB;
  const float available = (float)(buffer.f_bfree * buffer.f_frsize) / GB;
  const float used = total - available;

  Disk_stats disk;
  disk.used = used;
  disk.total = total;
  return disk;
}

System_memory get_system_memory() {
  const char *memory_device = "/proc/meminfo";
  const char *numbers = "0123456789";

  int memVars[8];
  /*
      0 MemTotal			1
      1 MemFree				2
      2 Bufferes			4
      3 Cached				5
      4 SwapTotal			15
      5 SwapFree			16
      6 Shmem					21
      7 SReclaimable	24
  */

  fp = fopen(memory_device, "r");

  char *line_buff;
  size_t line_buff_size = 0;
  getline(&line_buff, &line_buff_size, fp);

  int line_number = 0;
  int i = 0;
  while (line_number <= 24) {
    line_number++;
    if (line_number == 1 || line_number == 2 || line_number == 4 ||
        line_number == 5 || line_number == 15 || line_number == 16 ||
        line_number == 21 || line_number == 24) {
      int num = atoi(strpbrk(line_buff, numbers));
      memVars[i] = num;
      i++;
    }
    getline(&line_buff, &line_buff_size, fp);
  }
  fclose(fp);

  // (SwapTotal-SwapFree)
  float swap_used_bytes = memVars[4] - memVars[5];
  float swap_used = swap_used_bytes / MB;
  float swap_total = ((float)memVars[4]) / MB;

  // (((MemTotal-MemFree)+Shmem)-(Buffers+(Cached+SReclaimable)))
  float mem_used_bytes = ((memVars[0] - memVars[1]) + memVars[6]) -
                         (memVars[2] + memVars[3] + memVars[7]);
  float mem_used = mem_used_bytes / MB;
  float mem_total = ((float)memVars[0]) / MB;

  System_memory sys_mem;
  sys_mem.memory = mem_used;
  sys_mem.memory_total = mem_total;
  sys_mem.swap = swap_used;
  sys_mem.swap_total = swap_total;

  return sys_mem;
}

int main(int argc, char *argv[]) {
  // memory and swap
  System_memory sys_mem = get_system_memory();

  // current
  float current = get_current();

  // temperature
  Temperature temperature = get_temperature();

  // size size and usage
  Disk_stats disks[DISK_DEVICES_COUNT];
  for (int i=0; i<DISK_DEVICES_COUNT; i++) {
    disks[i] = get_disk_stats(DISK_DEVICES[i]);
  } 


  // refresh on click
  int internal_id = 0;
  if (argc == 2) {
    internal_id = atoi(argv[1]);
  }
	printf("<txtclick>xfce4-panel --plugin-event=genmon-%d:refresh:bool:true</txtclick>\n", internal_id);
  // /refresh on click


  // title text
  printf("<txt><span font-family='sans' font-weight='bold' color='#BBC3C8'>");
  // {mem} {swap}  {current}  {temperature} 
  printf("%.2fG %.2fG  %.3fA  %d°C ",
		sys_mem.memory, sys_mem.swap,
		current, temperature.max_temperature
  );
	// {disk /} {disk /home} ...
  for (int i = 0; i < DISK_DEVICES_COUNT; i++) {
    printf(" %.1fG", disks[i].used);
  }
  printf("</span></txt>\n");
  // /title text


  // toolbar text
	printf("<tool><span font-family='monospace'>");
  // 'Memory              1.00G/8.00G'
	printf("%-20s%.2fG/%.2fG\n", "Memory", sys_mem.memory, sys_mem.memory_total);
  // 'Swap                0.56G/2.00G'
	printf("%-20s%.2fG/%.2fG\n", "Swap", sys_mem.swap, sys_mem.swap_total);
  // 'Current             0.000A'
	printf("%-20s%.3fA\n", "Current", current);
  // 'Temperature         43°C 42°C ...
	printf("%-20s", "Temperature");
	for (int i = 0; i < TEMPERATURE_DEVICES_COUNT; i++) {
		printf("%d°C", temperature.temperatures[i]);
		if (i != 3) printf(" ");
	}
	printf("\n");

  // 'Disk /              23.0G/80.0G'
  for (int i = 0; i < DISK_DEVICES_COUNT; i++) {
    printf("Disk %-15s%.1fG/%.1fG", DISK_DEVICES[i], disks[i].used, disks[i].total);
    if (i != DISK_DEVICES_COUNT-1) {
      printf("\n");
    }
  }
	printf("</span></tool>");
  // /toolbar text


  return 0;
}
