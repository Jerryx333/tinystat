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

## Reproduce

```sh
bash scripts/build.sh
bash scripts/benchmark.sh 300
python3 scripts/report.py
# Quit normal TinyStat instances before this paired test:
bash scripts/workload-check.sh
```

Each UI benchmark warms up for 11 seconds, then records the selected duration. Do not interact with benchmark windows: that changes the scenario. Reports are written under ignored `reports/`; do not publish local reports without reviewing their content.

CPU comes from process user + system CPU time divided by elapsed time. RSS and physical footprint come from process resource APIs. Peak values are periodically sampled, not absolute maxima. Package-idle wakeups do not measure all wakeups. First-panel sample latency is not window-animation latency. Script wall time differs from sampled process CPU time.

Closed state must add zero GPU/process samples, overview zero process samples; `scripts/report.py` asserts these gates. Hardware tests and performance runs require a real suitable Mac; CI compilation does not prove sensor coverage or performance.
