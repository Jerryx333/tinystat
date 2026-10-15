#!/bin/bash
# Measure fixed UI states sequentially; run: bash scripts/benchmark.sh [seconds=300]
# Requires built TinyStat.app and macOS; keep benchmark windows untouched.
set -euo pipefail
cd "$(dirname "$0")/.."
duration="${1:-300}"
mkdir -p reports
for mode in closed overview cpu memory advanced after-close; do
  build/TinyStat.app/Contents/MacOS/TinyStat --benchmark "$mode" "$duration" "reports/$mode.json"
done
python3 - <<'PY'
import json
from pathlib import Path
for mode in ('closed','overview','cpu','memory','advanced','after-close'):
    d=json.loads(Path(f'reports/{mode}.json').read_text())
    print(f"{mode:12} CPU {d['cpu_percent_one_core']:.3f}% RSS {d['rss_bytes']/1048576:.1f} MiB footprint {d['physical_footprint_bytes']/1048576:.1f} MiB")
PY
