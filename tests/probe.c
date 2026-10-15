// Verify real host telemetry; run: bash scripts/verify.sh
// Requires macOS SDK, read-only APIs, no elevated permissions.
#include "../Sources/Telemetry.h"
#include <stdio.h>
#include <unistd.h>
#include <math.h>
int main(void){
 TSBasic b;ts_basic(&b,true);usleep(1100000);ts_basic(&b,true);
 TSGPU g=ts_gpu();TSTemperature c=ts_temperature(false),t=ts_temperature(true);
 static TSProcess p[16384];TSProcessCoverage coverage=ts_processes(p,16384);
 printf("CPU %.2f%% cores %d; memory %.2f / %.2f GB pressure %d; GPU %.1f%%\n",b.user+b.system,b.cores_count,b.used/1e9,b.total/1e9,b.pressure,g.percent);
 printf("CPU maximum %.2f°C (%d/%d); GPU maximum %.2f°C (%d/%d)\n",c.maximum,c.found,c.expected,t.maximum,t.found,t.expected);
 printf("processes read %d / %d skipped %d truncated %d error %d\n",coverage.read,coverage.listed,coverage.skipped,coverage.truncated,coverage.error);
 ts_close();
 return !(b.cpu_valid&&b.memory_valid&&b.pressure_valid&&g.valid&&c.found==c.expected&&t.found==t.expected&&coverage.read>0&&!coverage.error&&!coverage.truncated&&isfinite(c.maximum)&&isfinite(t.maximum));
}
