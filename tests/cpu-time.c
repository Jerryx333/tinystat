// Verify process CPU units against getrusage with a real bounded CPU workload.
// Run: bash scripts/verify.sh
// Requires macOS SDK; no process names or private telemetry are logged.
#include "../Sources/Telemetry.h"
#include <sys/resource.h>
#include <unistd.h>
#include <stdio.h>
#include <math.h>
static TSProcess rows[4096];
static uint64_t own_cpu(void) {
    TSProcessCoverage c=ts_processes(rows,4096);
    for(int i=0;i<c.read;i++)if(rows[i].pid==getpid())return rows[i].cpu_ns;
    return 0;
}
static double cpu(void) {struct rusage u;getrusage(RUSAGE_SELF,&u);return u.ru_utime.tv_sec+u.ru_stime.tv_sec+(u.ru_utime.tv_usec+u.ru_stime.tv_usec)/1e6;}
int main(void) {
    uint64_t a=own_cpu();double x=cpu();volatile unsigned long v=0;
    for(unsigned long i=0;i<100000000;i++)v+=i;
    double y=cpu();uint64_t b=own_cpu();double measured=(b-a)/1e9,reference=y-x;
    printf("CPU unit check: telemetry %.4fs, getrusage %.4fs\n",measured,reference);
    ts_close();return !(a>0 && b>a && reference>0.05 && fabs(measured-reference)<0.04);
}
