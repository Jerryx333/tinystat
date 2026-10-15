// Fixed single-thread CPU workload for paired off/on comparison.
// Run: bash scripts/workload-check.sh
// Requires Apple clang; workload is bounded and prints only timing/checksum.
#include <stdio.h>
#include <stdint.h>
#include <time.h>
#include <sys/resource.h>
static double wall(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
int main(void){
    double start=wall();volatile uint64_t value=1;
    for(uint64_t i=0;i<500000000ULL;i++)value=value*6364136223846793005ULL+1;
    struct rusage r;getrusage(RUSAGE_SELF,&r);
    double cpu=r.ru_utime.tv_sec+r.ru_stime.tv_sec+(r.ru_utime.tv_usec+r.ru_stime.tv_usec)/1e6;
    printf("{\"elapsed_seconds\":%.6f,\"cpu_seconds\":%.6f,\"max_rss_bytes\":%ld,\"checksum\":%llu}\n",wall()-start,cpu,r.ru_maxrss,(unsigned long long)value);
}
