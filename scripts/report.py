#!/usr/bin/env python3
# Summarize telemetry and verify demand gates; run: python3 scripts/report.py [reports-dir]
# Requires Python 3 and completed reports from scripts/benchmark.sh.
import json, sys
from pathlib import Path
root = Path(__file__).resolve().parent.parent
reports = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'reports'
lines = ['# TinyStat 本机性能实测', '', '单核 100% 口径；RSS 与 physical footprint 分开报告。每场预热 11 秒，测量时长见表。', '', '| 场景 | 秒 | CPU % | RSS MiB | Footprint MiB | 采样峰值 RSS MiB |', '|---|---:|---:|---:|---:|---:|']
for mode in ('closed', 'overview', 'cpu', 'memory', 'advanced', 'after-close'):
    d = json.loads((reports / f'{mode}.json').read_text())
    a, b = d['sampling_counters_at_start'], d['sampling_counters_including_warmup']
    if mode in ('closed', 'after-close'):
        assert b['process_samples'] == a['process_samples'], f'{mode}: hidden process reads'
        assert b['gpu_samples']-a['gpu_samples'] == b['basic_samples']-a['basic_samples'], f'{mode}: GPU history cadence differs from basic sampling'
    if mode == 'overview':
        assert b['process_samples'] == a['process_samples'], 'overview process reads'
    lines.append(f"| {mode} | {d['elapsed_seconds']:.1f} | {d['cpu_percent_one_core']:.3f} | {d['rss_bytes']/1048576:.1f} | {d['physical_footprint_bytes']/1048576:.1f} | {d['peak_sampled_rss_bytes']/1048576:.1f} |")
lines += ['', '测量环境未随报告保存，请记录实际硬件、系统版本、构建版本与后台负载。峰值为周期采样观察值，未测绝对峰值。package-idle wakeups 见原始 JSON，不等于总唤醒数。', '', '内部目标：包体 ≤5 MB；关闭 CPU ≤0.1%、可见 CPU ≤0.5%、关闭 RSS ≤40 MiB。目标用于暴露差距，不将超标值改换口径为达标。']
workload = reports / 'workload.json'
if workload.exists():
    w=json.loads(workload.read_text())
    lines += ['', '固定计算任务对照（按 workload.json 汇总；版本及采样间隔需核对同批原始报告）：', f"关闭中位 {w['median_off_seconds']:.6f}s，开启 {w['median_on_seconds']:.6f}s，变化 {w['median_change_percent']:.3f}%。不能据此宣称零影响；未覆盖 GPU、磁盘或视频工作负载。"]
(reports / 'PERFORMANCE.md').write_text('\n'.join(lines) + '\n')
print('\n'.join(lines))
