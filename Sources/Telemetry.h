#ifndef TINYSTAT_TELEMETRY_H
#define TINYSTAT_TELEMETRY_H
#include <stdint.h>
#include <stdbool.h>
#define TS_MAX_CORES 256

typedef struct {
    bool cpu_valid, memory_valid, pressure_valid, swap_valid, swap_rate_valid;
    double user, system, used, app, wired, compressed, cache, total;
    double swap_used, swap_total, swap_in, swap_out, uptime, load[3];
    int pressure, cores_count;
    double cores[TS_MAX_CORES];
} TSBasic;
typedef struct { bool valid; double percent, memory; } TSGPU;
typedef struct { double maximum; int found, expected; } TSTemperature;
typedef struct { int pid; uint64_t start, cpu_ns, memory; } TSProcess;
typedef struct { int listed, read, skipped; bool truncated; int error; } TSProcessCoverage;
void ts_basic(TSBasic *out, bool cores);
void ts_reset(void);
TSGPU ts_gpu(void);
TSTemperature ts_temperature(bool gpu);
TSProcessCoverage ts_processes(TSProcess *out, int capacity);
void ts_process_name(int pid, uint64_t start, char *name, int capacity);
typedef struct { double cpu_seconds, rss, footprint; uint64_t wakeups; } TSResources;
TSResources ts_resources(void);
void ts_close(void);
#endif
