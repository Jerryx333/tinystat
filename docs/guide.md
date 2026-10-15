# Usage and implementation

[Back to README](../README.en.md) | [中文](guide.zh-CN.md)

## Interaction

The menu bar shows health, CPU usage and temperature, and memory usage. Click to open; leave the panel or click outside to close. CPU, GPU and memory rows lead to the same details page. Switch process ranking between CPU and memory. Additional metrics are collapsed initially and can scroll on smaller screens. Settings control the open-panel 5/10-second interval, login startup and quitting; appearance follows macOS.

Login startup is off by default and registered only when selected. Login behavior, display transitions and long sleep/resume cycles still need broader testing. Aggregate CPU and newly opened process CPU rankings need a second sample to calculate deltas.

## Metric definitions

- Aggregate CPU uses 100% for the whole machine; process CPU uses 100% per core and may exceed 100%.
- CPU/GPU temperatures are the maximum of their recognized sensors: 10 CPU and 4 GPU mappings for M1. `*` means partial coverage; failed reads show unavailable. Temperature alone does not establish overload.
- Health prioritizes macOS thermal state and memory pressure. Sampled CPU above 90% for at least 10 seconds indicates sustained load.
- Used memory is application + wired + compressed. Application memory is internal minus purgeable. Units are binary, with GB/MB UI labels. Cache estimates reclaimable purgeable + external memory.
- GPU memory is unified system memory and must not be counted twice.
- Process memory is physical footprint. At most 4096 readable processes are retained, with truncation disclosed. Inaccessible or exited processes are counted in coverage. Only the top five names are queried; PID and start time protect against PID reuse.
- Additional metrics include per-core load, load averages, uptime, GPU memory, application/wired/compressed/cache memory and swap rates. Rates without a baseline display a dash.

## Resources and privacy

One serial sampling queue and one timer with 500ms leeway. Closed refresh is 10 seconds, open defaults to 5 seconds, and CPU temperatures refresh every 10 seconds. GPU readings are immediate on each open, then GPU temperatures refresh every 10 seconds; scheduling can extend intervals. GPU reads occur only in visible overview/details, process reads only in details, and per-core reads only with additional metrics expanded. Rapid basic samples reuse recent values; reopening still triggers GPU reads. Pointer exit is event-driven, without continuous polling. System or display sleep stops sampling.

History is memory-only: two minutes and at most 64 points. No database, network calls, resident child processes or periodic shell commands. Normal operation writes no logs; explicit benchmarks write reports. Settings use the `local.tinystat.app` preferences domain.

SMC commands are limited to read-only key-info/read. The app does not change fan or hardware settings. This interface has no public stability guarantee. See [third-party references](../THIRD_PARTY.md).

## Build, update and remove

`bash scripts/build.sh` creates an ad-hoc-signed `build/TinyStat.app`. `bash scripts/install.sh` installs to `~/Applications/TinyStat.app`; identical installs are idempotent and running versions cannot be replaced. Old bundles are backed up under `~/Library/Application Support/TinyStat/Backups`. Failed staging paths are reported, without silently deleting data.

Disable login startup in settings and quit before moving the app to Trash. Preferences and backups may be removed separately; no uninstall script deletes them automatically. Source files and benchmark reports are also retained.

## Menu-bar position and diagnostics

First launch uses a position near the right edge and a stable item identifier. Subsequent launches preserve the saved position. Command-drag to rearrange. Third-party managers can still hide the item; their configuration is not cleared.

Quit TinyStat first, then run `"$HOME/Applications/TinyStat.app/Contents/MacOS/TinyStat" --diagnose-status` to print the menu-bar frame and screen bounds after two seconds. Press Ctrl-C when finished. If an instance is already running, the new process exits without diagnostics. Diagnostics are opt-in. Remove private environment details before sharing.

## Tests

`bash scripts/check.sh` builds and checks the signature and documentation. `bash scripts/verify.sh` also checks hardware sensors, compares real process CPU work against getrusage, and tests rapid sampling, rank changes, reopening and resets. Hardware verification requires the validated M1 Max sensor set; virtual machines and other models are not equivalent passes.

[Performance testing](performance.md) covers six UI states and paired workloads. Startup registration, other chips and multiple displays still require real environment validation; state tests do not prove that compatibility.
