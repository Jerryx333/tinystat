#!/usr/bin/env python3
# Cross-check TinyStat telemetry against host counters, IORegistry and optional Thermo.
# Run: python3 scripts/accuracy-check.py [--thermo /path/to/thermo] [--output reports/accuracy]
# Requires macOS Apple SDK and Python 3; read-only, no elevated permissions.
import argparse, datetime, hashlib, json, math, platform, plistlib, re, subprocess, tempfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--thermo', type=Path)
parser.add_argument('--output', type=Path, default=Path('reports/accuracy'))
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
args.output.mkdir(parents=True, exist_ok=True)
source = r'''
#include "Telemetry.h"
#include <mach/mach.h>
#include <stdio.h>
#include <unistd.h>
int main(void) {
 TSBasic b; ts_basic(&b,false);
 host_cpu_load_info_data_t a={0},z={0}; mach_msg_type_number_t n=HOST_CPU_LOAD_INFO_COUNT;
 mach_port_t host=mach_host_self();
 if(host_statistics(host,HOST_CPU_LOAD_INFO,(host_info_t)&a,&n)!=KERN_SUCCESS)return 1;
 usleep(1100000);ts_basic(&b,false);n=HOST_CPU_LOAD_INFO_COUNT;
 if(host_statistics(host,HOST_CPU_LOAD_INFO,(host_info_t)&z,&n)!=KERN_SUCCESS)return 1;
 unsigned long long total=0,idle=0;for(int i=0;i<4;i++){unsigned d=z.cpu_ticks[i]-a.cpu_ticks[i];total+=d;if(i==CPU_STATE_IDLE)idle=d;}
 TSGPU g=ts_gpu();TSTemperature c=ts_temperature(false),t=ts_temperature(true);
 if(!b.cpu_valid||!b.memory_valid||!g.valid||!total||!c.found||!t.found)return 2;
 printf("{\"cpu\":%.6f,\"reference_cpu\":%.6f,\"used\":%.0f,\"total\":%.0f,\"gpu\":%.6f,\"cpu_temperature\":%.6f,\"gpu_temperature\":%.6f,\"cpu_sensors\":%d,\"gpu_sensors\":%d}",b.user+b.system,100.0*(total-idle)/total,b.used,b.total,g.percent,c.maximum,t.maximum,c.found,t.found);
 ts_close();mach_port_deallocate(mach_task_self(),host);return 0;
}
'''
def command(*argv):
    return subprocess.check_output([str(a) for a in argv], text=True)

def gpu_reference():
    data = subprocess.check_output(['ioreg', '-r', '-c', 'AGXAccelerator', '-a'])
    devices = plistlib.loads(data)
    values = [d['PerformanceStatistics']['Device Utilization %'] for d in devices
              if 'Device Utilization %' in d.get('PerformanceStatistics', {})]
    if len(values) != 1:
        raise RuntimeError('This verification requires exactly one readable AGX device')
    return values[0]

rows = []
with tempfile.TemporaryDirectory(prefix='tinystat-accuracy-') as tmp:
    c = Path(tmp) / 'probe.c'; binary = Path(tmp) / 'probe'; c.write_text(source)
    subprocess.run(['xcrun', 'clang', '-O2', '-Wall', '-Wextra', '-Werror', '-I', str(root/'Sources'),
                    str(c), str(root/'Sources/Telemetry.c'), '-framework', 'IOKit', '-framework', 'CoreFoundation', '-o', str(binary)], check=True)
    for _ in range(5):
        before_gpu = gpu_reference()
        sample = json.loads(command(binary))
        after_gpu = gpu_reference()
        vm = command('vm_stat')
        page = int(re.search(r'page size of (\d+) bytes', vm)[1])
        fields = {k.strip(): int(v) for k, v in re.findall(r'^([^:]+):\s+(\d+)\.', vm, re.M)}
        used = (max(0,fields['Anonymous pages']-fields['Pages purgeable'])+fields['Pages wired down']+fields['Pages occupied by compressor'])*page
        sample.update(reference_used=used, gpu_before=before_gpu, gpu_after=after_gpu,
                      memory_delta_percentage_points=abs(sample['used']-used)/sample['total']*100,
                      cpu_delta_percentage_points=abs(sample['cpu']-sample['reference_cpu']))
        if args.thermo:
            thermo = json.loads(command(args.thermo, 'temps', '--json'))
            sample['thermo'] = {}
            for group in ('CPU', 'GPU'):
                readings = [r for r in thermo['temperatures'] if r['group']==group and r['known'] and math.isfinite(r['value'])]
                smc = [r for r in readings if not r['key'].startswith('hid:')]
                sample['thermo'][group] = dict(smc_max=max(r['value'] for r in smc), all_max=max(r['value'] for r in readings), smc_count=len(smc))
        rows.append(sample)
        print(json.dumps(sample), flush=True)
result = dict(environment=dict(at=datetime.datetime.now(datetime.timezone.utc).isoformat(), macos=platform.mac_ver()[0], chip=command('sysctl','-n','machdep.cpu.brand_string').strip(), source_sha256=hashlib.sha256((root/'Sources/Telemetry.c').read_bytes()).hexdigest()), samples=rows, limits='Sequential live reads, not simultaneous. CPU reference windows nearly coincide; memory/GPU/temperature can change between reads. Temperature scope: mapped M1 SMC keys, excludes HID. Other hardware unverified.')
(args.output/'comparison.json').write_text(json.dumps(result, indent=2)+'\n')
if any(r['cpu_delta_percentage_points']>1 or r['memory_delta_percentage_points']>1 for r in rows):
    raise SystemExit('CPU/memory exceeded 1 percentage point tolerance; inspect raw samples')
if args.thermo:
    for r in rows:
        for group in ('CPU', 'GPU'):
            if r[group.lower()+'_sensors'] != r['thermo'][group]['smc_count'] or abs(r[group.lower()+'_temperature']-r['thermo'][group]['smc_max']) > 2:
                raise SystemExit('Temperature coverage/value mismatch; inspect sequential timing and sensor scope')
print('Same-source CPU/memory consistency PASS. ' + ('Thermo temperature coverage/value comparison PASS. ' if args.thermo else 'Thermo temperature comparison NOT RUN. ') + 'GPU utilization logged only; not a simultaneous accuracy assertion.')
