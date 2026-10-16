// Read-only macOS telemetry. Build via scripts/build.sh; requires Apple SDK.
#include "Telemetry.h"
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <sys/sysctl.h>
#include <sys/resource.h>
#include <libproc.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <errno.h>
#include <stddef.h>

static mach_port_t host;
static uint32_t previous_cpu[4], previous_cores[TS_MAX_CORES*4];
static bool have_cpu, have_cores, have_swap;
static uint64_t previous_in, previous_out;
static double previous_time;
static io_connect_t smc;
static io_service_t accelerator;
static double monotonic(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
static bool sysread(const char *name, void *p, size_t size) { size_t actual=size; return sysctlbyname(name,p,&actual,NULL,0)==0 && actual==size; }
void ts_reset(void) { have_cpu=false; have_cores=false; have_swap=false; }
static double fraction(const uint32_t *now, const uint32_t *old, int part) {
    uint64_t total=0; for(int i=0;i<4;i++) total+=(uint32_t)(now[i]-old[i]);
    return total ? 100.0*(uint32_t)(now[part]-old[part])/total : NAN;
}
void ts_basic(TSBasic *o, bool cores) {
    memset(o,0,sizeof(*o)); if(!host) host=mach_host_self();
    host_cpu_load_info_data_t cpu={0}; mach_msg_type_number_t count=HOST_CPU_LOAD_INFO_COUNT;
    if(host_statistics(host,HOST_CPU_LOAD_INFO,(host_info_t)&cpu,&count)==KERN_SUCCESS) {
        if(have_cpu) { o->user=fraction(cpu.cpu_ticks,previous_cpu,CPU_STATE_USER)+fraction(cpu.cpu_ticks,previous_cpu,CPU_STATE_NICE); o->system=fraction(cpu.cpu_ticks,previous_cpu,CPU_STATE_SYSTEM); o->cpu_valid=isfinite(o->user) && isfinite(o->system); }
        memcpy(previous_cpu,cpu.cpu_ticks,sizeof(previous_cpu)); have_cpu=true;
    } else have_cpu=false;
    vm_statistics64_data_t vm={0}; count=HOST_VM_INFO64_COUNT; uint64_t total=0;
    if(host_statistics64(host,HOST_VM_INFO64,(host_info64_t)&vm,&count)==KERN_SUCCESS && sysread("hw.memsize",&total,sizeof(total))) {
        double page=vm_kernel_page_size;
        o->total=(double)total; o->wired=vm.wire_count*page; o->compressed=vm.compressor_page_count*page;
        o->app=fmax(0,((double)vm.internal_page_count-vm.purgeable_count)*page);
        o->used=fmin(o->total,o->app+o->wired+o->compressed); o->cache=(vm.purgeable_count+(double)vm.external_page_count)*page; o->memory_valid=true;
        double now=monotonic();
        if(have_swap && now>previous_time && vm.swapins>=previous_in && vm.swapouts>=previous_out) { o->swap_rate_valid=true; o->swap_in=(vm.swapins-previous_in)*page/(now-previous_time); o->swap_out=(vm.swapouts-previous_out)*page/(now-previous_time); }
        previous_in=vm.swapins; previous_out=vm.swapouts; previous_time=now; have_swap=true;
    } else have_swap=false;
    o->pressure_valid=sysread("kern.memorystatus_vm_pressure_level",&o->pressure,sizeof(o->pressure));
    struct xsw_usage swap={0}; if(sysread("vm.swapusage",&swap,sizeof(swap))) { o->swap_valid=true; o->swap_used=swap.xsu_used; o->swap_total=swap.xsu_total; }
    if(getloadavg(o->load,3)!=3) for(int i=0;i<3;i++)o->load[i]=NAN;
    o->uptime=NAN; struct timeval boot={0}; int mib[2]={CTL_KERN,KERN_BOOTTIME}; size_t size=sizeof(boot);
    if(sysctl(mib,2,&boot,&size,NULL,0)==0) o->uptime=difftime(time(NULL),boot.tv_sec);
    if(cores) {
        natural_t n=0; processor_info_array_t info=NULL; mach_msg_type_number_t length=0;
        if(host_processor_info(host,PROCESSOR_CPU_LOAD_INFO,&n,&info,&length)==KERN_SUCCESS) {
            int bounded=n>TS_MAX_CORES?TS_MAX_CORES:(int)n;
            if(length >= (unsigned)bounded*4) {
                const uint32_t *ticks=(const uint32_t*)info;
                if(have_cores) { o->cores_count=bounded; for(int i=0;i<bounded;i++)o->cores[i]=100-fraction(ticks+i*4,previous_cores+i*4,CPU_STATE_IDLE); }
                memcpy(previous_cores,ticks,bounded*4*sizeof(uint32_t)); have_cores=true;
            }
            vm_deallocate(mach_task_self(),(vm_address_t)info,length*sizeof(integer_t));
        } else have_cores=false;
    } else have_cores=false;
}
TSGPU ts_gpu(void) {
    TSGPU g={.memory=NAN};
    if(!accelerator) accelerator=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AGXAccelerator"));
    if(!accelerator)return g;
    CFTypeRef property=IORegistryEntryCreateCFProperty(accelerator,CFSTR("PerformanceStatistics"),kCFAllocatorDefault,0);
    if(property && CFGetTypeID(property)==CFDictionaryGetTypeID()) {
        CFNumberRef use=CFDictionaryGetValue(property,CFSTR("Device Utilization %"));
        if(use && CFGetTypeID(use)==CFNumberGetTypeID() && CFNumberGetValue(use,kCFNumberDoubleType,&g.percent) && g.percent>=0 && g.percent<=100)g.valid=true;
        CFNumberRef mem=CFDictionaryGetValue(property,CFSTR("In use system memory"));
        g.memory=NAN; if(mem && CFGetTypeID(mem)==CFNumberGetTypeID())CFNumberGetValue(mem,kCFNumberDoubleType,&g.memory);
    }
    if(property)CFRelease(property);
    if(!g.valid){IOObjectRelease(accelerator);accelerator=0;}
    return g;
}
// AppleSMC user-client ABI. Commands are limited to key-info (9) and read (5).
typedef struct { uint8_t major,minor,build,reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version,length; uint32_t cpu,gpu,memory; } SMCLimits;
typedef struct { uint32_t size,type; uint8_t attributes; } SMCInfo;
typedef struct { uint32_t key; SMCVersion version; SMCLimits limits; SMCInfo info; uint8_t result,status,command; uint32_t data; uint8_t bytes[32]; } SMCPacket;
_Static_assert(sizeof(SMCPacket)==80,"SMC ABI size");
_Static_assert(offsetof(SMCPacket,command)==42,"SMC command offset");
static uint32_t fourcc(const char *key) { return (uint32_t)(uint8_t)key[0]<<24 | (uint32_t)(uint8_t)key[1]<<16 | (uint32_t)(uint8_t)key[2]<<8 | (uint8_t)key[3]; }
typedef struct { const char *key; SMCInfo info; } Sensor;
// SMC keys verified on M1 Max; HID sensors are not included. Missing keys remain partial.
static Sensor cpu_sensors[]={ {"Te00",{0}},{"Te01",{0}},{"Te02",{0}},{"Tp00",{0}},{"Tp01",{0}},{"Tp02",{0}},{"Tp04",{0}},{"Tp05",{0}},{"Tp06",{0}},{"Tp08",{0}},{"Tp09",{0}},{"Tp0A",{0}},{"Tp0C",{0}},{"Tp0D",{0}},{"Tp0E",{0}},{"Tp0G",{0}},{"Tp0H",{0}},{"Tp0I",{0}},{"Tp0K",{0}},{"Tp0L",{0}},{"Tp0M",{0}},{"Tp0O",{0}},{"Tp0P",{0}},{"Tp0Q",{0}},{"Tp0S",{0}},{"Tp0T",{0}},{"Tp0U",{0}},{"Tp0W",{0}},{"Tp0X",{0}},{"Tp0Y",{0}},{"Tp0a",{0}},{"Tp0b",{0}},{"Tp0c",{0}} };
static Sensor gpu_sensors[]={ {"TG0H",{0}},{"Tg04",{0}},{"Tg05",{0}},{"Tg0C",{0}},{"Tg0D",{0}},{"Tg0K",{0}},{"Tg0L",{0}},{"Tg0S",{0}},{"Tg0T",{0}} };
static bool call(SMCPacket *in,SMCPacket *out) { size_t length=sizeof(*out); memset(out,0,sizeof(*out)); return IOConnectCallStructMethod(smc,2,in,sizeof(*in),out,&length)==KERN_SUCCESS && length==sizeof(*out) && out->result==0; }
TSTemperature ts_temperature(bool gpu) {
    TSTemperature t={.maximum=NAN,.expected=gpu?(int)(sizeof(gpu_sensors)/sizeof(*gpu_sensors)):(int)(sizeof(cpu_sensors)/sizeof(*cpu_sensors))};
    // These mappings are scoped to M1 generation. Unknown models remain unsupported.
    char model[128]={0}; size_t model_size=sizeof(model); if(sysctlbyname("machdep.cpu.brand_string",model,&model_size,NULL,0)!=0 || !strstr(model,"Apple M1")) return t;
    if(!smc) { io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC")); if(!service)return t; kern_return_t result=IOServiceOpen(service,mach_task_self(),0,&smc); IOObjectRelease(service); if(result!=KERN_SUCCESS){smc=0;return t;} }
    Sensor *s=gpu?gpu_sensors:cpu_sensors;
    for(int i=0;i<t.expected;i++) {
        SMCPacket in={0},out={0}; in.key=fourcc(s[i].key);
        if(!s[i].info.size) { in.command=9; if(!call(&in,&out))continue; if(out.info.size!=4 && out.info.size!=2 && out.info.size!=8)continue; s[i].info=out.info; }
        in.info=s[i].info; in.command=5; if(!call(&in,&out)){s[i].info.size=0;continue;}
        double v=NAN;
        if(s[i].info.type==fourcc("flt ") && s[i].info.size==4) { float f;memcpy(&f,out.bytes,4);v=f; }
        else if(s[i].info.type==fourcc("ioft") && s[i].info.size==8) { uint64_t fixed;memcpy(&fixed,out.bytes,8);v=(double)fixed/65536.0; }
        else if(s[i].info.type==fourcc("sp78") && s[i].info.size==2) v=(int16_t)((out.bytes[0]<<8)|out.bytes[1])/256.0;
        if(isfinite(v) && v>0 && v<130) { if(!t.found || v>t.maximum)t.maximum=v; t.found++; }
    }
    return t;
}
TSProcessCoverage ts_processes(TSProcess *out,int capacity) {
    TSProcessCoverage c={0}; if(capacity<1){c.error=EINVAL;return c;}
    int bytes=proc_listpids(PROC_ALL_PIDS,0,NULL,0); if(bytes<=0){c.error=errno?errno:EIO;return c;}
    int slots=bytes/(int)sizeof(pid_t)+256; if(slots>65536){slots=65536;c.truncated=true;}
    pid_t *pids=calloc(slots,sizeof(pid_t)); if(!pids){c.error=ENOMEM;return c;}
    int actual=proc_listpids(PROC_ALL_PIDS,0,pids,slots*sizeof(pid_t)); if(actual<=0){c.error=errno?errno:EIO;free(pids);return c;}
    if(actual>=slots*(int)sizeof(pid_t))c.truncated=true;
    int n=actual/(int)sizeof(pid_t);
    mach_timebase_info_data_t scale; mach_timebase_info(&scale);
    for(int i=0;i<n;i++) {
        if(pids[i]<=0)continue;c.listed++;
        if(c.read>=capacity){c.truncated=true;continue;}
        struct rusage_info_v2 usage={0};
        if(proc_pid_rusage(pids[i],RUSAGE_INFO_V2,(rusage_info_t*)&usage)!=0){c.skipped++;continue;}
        TSProcess *p=&out[c.read];memset(p,0,sizeof(*p));p->pid=pids[i];p->start=usage.ri_proc_start_abstime;p->cpu_ns=(uint64_t)(((__uint128_t)usage.ri_user_time+usage.ri_system_time)*scale.numer/scale.denom);p->memory=usage.ri_phys_footprint;
        c.read++;
    }
    free(pids);return c;
}
void ts_process_name(int pid,uint64_t start,char *name,int capacity) {
    if(capacity<1)return;
    struct rusage_info_v2 usage={0};
    if(proc_name(pid,name,(uint32_t)capacity)<=0 || proc_pid_rusage(pid,RUSAGE_INFO_V2,(rusage_info_t*)&usage)!=0 || usage.ri_proc_start_abstime!=start)
        snprintf(name,(size_t)capacity,"PID %d",pid);
    name[capacity-1]=0;
}
int ts_process_threads(int pid,uint64_t start) {
    struct proc_taskinfo info={0};
    if(proc_pidinfo(pid,PROC_PIDTASKINFO,0,&info,sizeof(info))!=sizeof(info) || !ts_process_matches(pid,start))return -1;
    return info.pti_threadnum;
}
void ts_close(void) { if(smc){IOServiceClose(smc);smc=0;}if(accelerator){IOObjectRelease(accelerator);accelerator=0;}if(host){mach_port_deallocate(mach_task_self(),host);host=0;}ts_reset(); }

TSResources ts_resources(void) {
    TSResources r={0};struct rusage usage={0};
    if(getrusage(RUSAGE_SELF,&usage)==0)r.cpu_seconds=usage.ru_utime.tv_sec+usage.ru_utime.tv_usec/1e6+usage.ru_stime.tv_sec+usage.ru_stime.tv_usec/1e6;
    struct rusage_info_v4 info={0};if(proc_pid_rusage(getpid(),RUSAGE_INFO_V4,(rusage_info_t*)&info)==0){r.rss=info.ri_resident_size;r.footprint=info.ri_phys_footprint;r.wakeups=info.ri_pkg_idle_wkups;}
    return r;
}

bool ts_process_matches(int pid,uint64_t start) {
    struct rusage_info_v2 usage={0};
    return pid>1 && start>0 && proc_pid_rusage(pid,RUSAGE_INFO_V2,(rusage_info_t*)&usage)==0 && usage.ri_proc_start_abstime==start;
}
int ts_process_status(int pid,uint64_t start) {
    struct rusage_info_v2 usage={0};
    if(pid<=1 || !start)return 3;
    if(proc_pid_rusage(pid,RUSAGE_INFO_V2,(rusage_info_t*)&usage)!=0)return errno==ESRCH ? 1:3;
    return usage.ri_proc_start_abstime==start ? 0:2;
}
int ts_process_parent(int pid,uint64_t start,int *parent,unsigned *uid,unsigned *ruid) {
    struct proc_bsdinfo b={0};
    if(proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&b,sizeof(b))!=sizeof(b) || !ts_process_matches(pid,start))return 0;
    *parent=(int)b.pbi_ppid;*uid=b.pbi_uid;*ruid=b.pbi_ruid;return 1;
}
int ts_process_path(int pid,uint64_t start,char *path,int capacity) {
    if(capacity<1)return 0;
    if(proc_pidpath(pid,path,(uint32_t)capacity)<=0 || !ts_process_matches(pid,start)){path[0]=0;return 0;}
    path[capacity-1]=0;return 1;
}

int ts_process_sample(int pid,uint64_t start,TSProcess *out) {
    struct rusage_info_v2 usage={0};
    if(proc_pid_rusage(pid,RUSAGE_INFO_V2,(rusage_info_t*)&usage)!=0)return errno==ESRCH ? 1:3;
    if(usage.ri_proc_start_abstime!=start)return 2;
    mach_timebase_info_data_t scale;mach_timebase_info(&scale);
    memset(out,0,sizeof(*out));out->pid=pid;out->start=start;out->memory=usage.ri_phys_footprint;
    out->cpu_ns=(uint64_t)(((__uint128_t)usage.ri_user_time+usage.ri_system_time)*scale.numer/scale.denom);return 0;
}
