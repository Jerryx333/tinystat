# Performance / 性能

[中文 README](../README.md) | [English README](../README.en.md)

Efficiency is a design constraint, not a promise of zero impact. 性能优先不等于零开销。

## Reference measurements

Short development runs on an M1 Max, 32 GiB, macOS 26.4; other applications remained active. These measurements predate the menu-bar position fix and are not release certification. Raw local reports and process data are not published.

| State | Refresh | Duration after warmup | CPU, one core = 100% | RSS | Physical footprint |
|---|---|---:|---:|---:|---:|
| Closed, UI never opened | 10s | 63s | 0.056% | 39.0 MiB | 14.4 MiB |
| Overview | 5s | 60s | 0.197% | 57.8 MiB | 30.0 MiB |
| CPU ranking | 5s | 60s | 0.285% | 60.8 MiB | 33.3 MiB |
| Memory ranking | 5s | 60s | 0.283% | 60.1 MiB | 32.5 MiB |
| Additional metrics | 5s | 60s | 0.372% | 62.5 MiB | 35.4 MiB |
| Closed after viewing details | 10s | 62s | 0.093% | 56.8 MiB | 28.8 MiB |

Internal targets: bundle ≤5 MB, closed CPU ≤0.1%, visible CPU ≤0.5%, closed RSS ≤40 MiB. **RSS after viewing the UI missed the target.** AppKit retains resources after panels close. RSS and physical footprint are distinct measurements and cannot be substituted to claim a pass.

A three-round paired single-thread workload with at least 30 seconds per group measured median elapsed times of 1.019843s off and 1.020116s on (+0.027%). Round directions varied. This used the earlier 5-second closed refresh and does not establish zero impact or cover GPU, disk or video workloads.

## Build and allocation optimization (2026-10-15)

Removing local/debug symbols before signing reduced the measured app bundle from 262,839 to 198,023 bytes (24.7%). The build retains `build/TinyStat.unstripped` outside the app for local symbol lookup. No runtime dependency was added.

Process buffers are now allocated only for a visible ranking and released when leaving it. Heap inspection after viewing a ranking and closing the panel confirmed that the 147,456-byte process-array allocation and the previously retained 81,920-byte CPU-counter dictionary were absent. This proves those allocations were released, not an equivalent reduction in RSS or physical footprint. Login-item status is queried only when opening Settings.

Follow-up runs were affected by active background workloads and macOS memory-pressure level 2. CPU/RSS varied enough that no overall CPU or resident-memory reduction is claimed. AppKit/font/graphics retention after opening the UI remains; the closed RSS target is not established by this change.

## Reproduce

```sh
bash scripts/build.sh
bash scripts/benchmark.sh 300
python3 scripts/report.py
# Quit normal TinyStat instances before this paired test:
bash scripts/workload-check.sh
```

To keep comparison runs separate, pass a report directory and optionally an app bundle:

```sh
bash scripts/benchmark.sh 300 reports/before /path/to/before/TinyStat.app
bash scripts/benchmark.sh 300 reports/after build/TinyStat.app
python3 scripts/report.py reports/before
python3 scripts/report.py reports/after
```

Relative paths passed to `benchmark.sh` resolve from the repository root. `report.py` resolves an explicit relative directory from the current working directory.

Each UI benchmark warms up for 11 seconds, then records the selected duration. Do not interact with benchmark windows: that changes the scenario. Reports are written under ignored `reports/`; do not publish local reports without reviewing their content.

CPU comes from process user + system CPU time divided by elapsed time. RSS and physical footprint come from process resource APIs. Peak values are periodically sampled, not absolute maxima. Package-idle wakeups do not measure all wakeups. First-panel sample latency is not window-animation latency. Script wall time differs from sampled process CPU time.

Closed state must add zero process samples and one GPU usage read per basic sample; overview adds zero process samples; `scripts/report.py` asserts these gates. Hardware tests and performance runs require a real suitable Mac; CI compilation does not prove sensor coverage or performance.

## Assistant UI (2026-10-15)

The native overview/chat build is approximately 0.5 MB, excluding Codex/Claude CLIs. The earlier six-state table describes the previous detail-page interface; `cpu`, `memory`, and `advanced` benchmark modes now exercise retained sampler paths rather than visible product pages. They are not current UI performance claims.

An interactive UI smoke run changed pages during measurement, so its CPU/RSS results are not a fixed-state benchmark and are excluded. Full equivalent before/after tasks, token usage and peak process-family memory for live diagnosis have not yet been measured. Offline contract tests do not establish model performance. Model calls are explicit, with a 120-second request deadline, 1 MiB stdout cap, bounded conversation history and process-group cleanup; the external CLI can still dominate memory and CPU while a request runs.
