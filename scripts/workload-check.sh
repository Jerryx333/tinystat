#!/bin/bash
# Paired workload without/with TinyStat; run: bash scripts/workload-check.sh
# Requires Python 3 + Apple clang; close normal TinyStat first, leave test UI untouched.
set -euo pipefail
cd "$(dirname "$0")/.."
if pgrep -x TinyStat >/dev/null; then echo 'Close TinyStat before paired test.' >&2; exit 1; fi
mkdir -p build reports
xcrun clang -O2 tests/workload.c -o build/test-workload
python3 - <<'PY'
import json, subprocess, time, statistics
from pathlib import Path
rows=[]
for cycle in range(3):
    for mode in (('off','on') if cycle%2==0 else ('on','off')):
        app=None
        if mode=='on':
            app=subprocess.Popen(['build/TinyStat.app/Contents/MacOS/TinyStat','--benchmark','closed','40',f'reports/workload-app-{cycle}.json'])
        samples=[]
        try:
            if app is not None: time.sleep(11)
            deadline=time.monotonic()+30
            while time.monotonic()<deadline:
                samples.append(json.loads(subprocess.check_output(['build/test-workload'])))
            if app is not None and app.wait(timeout=30)!=0:
                raise RuntimeError('benchmark failed')
        finally:
            if app is not None and app.poll() is None:
                app.terminate()
                try: app.wait(timeout=5)
                except subprocess.TimeoutExpired: app.kill(); app.wait()
        rows.append({'cycle':cycle,'mode':mode,'samples':samples})
off=[s['elapsed_seconds'] for r in rows if r['mode']=='off' for s in r['samples']]
on=[s['elapsed_seconds'] for r in rows if r['mode']=='on' for s in r['samples']]
result={'runs':rows,'median_off_seconds':statistics.median(off),'median_on_seconds':statistics.median(on),'median_change_percent':(statistics.median(on)/statistics.median(off)-1)*100,'limitation':'One fixed single-thread workload on a busy host; not proof of zero impact or other workloads.'}
Path('reports/workload.json').write_text(json.dumps(result,indent=2))
print(json.dumps({k:v for k,v in result.items() if k!='runs'},indent=2))
PY
