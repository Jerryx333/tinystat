#!/bin/bash
# Measure fixed UI states; run: bash scripts/benchmark.sh [seconds=300] [output=reports] [app=build/TinyStat.app]
# Requires built TinyStat.app and macOS; keep benchmark windows untouched.
set -euo pipefail
cd "$(dirname "$0")/.."
duration="${1:-300}"
output="${2:-reports}"
app="${3:-build/TinyStat.app}"
mkdir -p "$output"
for mode in closed overview cpu memory advanced after-close; do
  "$app/Contents/MacOS/TinyStat" --benchmark "$mode" "$duration" "$output/$mode.json"
done
python3 - "$output" <<'PY'
import json, sys
from pathlib import Path
for mode in ('closed','overview','cpu','memory','advanced','after-close'):
    d=json.loads((Path(sys.argv[1])/f'{mode}.json').read_text())
    print(f"{mode:12} CPU {d['cpu_percent_one_core']:.3f}% RSS {d['rss_bytes']/1048576:.1f} MiB footprint {d['physical_footprint_bytes']/1048576:.1f} MiB")
PY
