# TinyStat

[中文](README.md) | [English](README.en.md)

CPU, GPU, memory and temperatures in a small native macOS menu-bar monitor.

## Why it exists

Full system monitors often include panels and background work you never use. TinyStat puts essential readings in the menu bar. Click for a compact overview; move the pointer away to close it. CPU/GPU and memory share one detail view.

- Separate CPU and GPU temperatures, with system thermal state and memory pressure indicating strain.
- Top five processes, sortable by CPU or memory; additional metrics stay collapsed.
- Refreshes every 10 seconds while closed and every 5 seconds by default while open. GPU, process and per-core readings depend on the visible page.
- Swift, AppKit and a small C telemetry bridge. System frameworks only, with no network requests or third-party runtime.

## Current status

**Early usable version with limited compatibility coverage.** Targets Apple Silicon and macOS 13+. Hardware validation covers only M1 Max on macOS 26.4; earlier OS versions are deployment targets, not verified runtime support. The UI is currently Chinese-only; temperature mappings cover only the M1 family. Other chips show temperatures as unavailable instead of guessing sensor identities.

This is not a complete iStat Menus replacement: no network speed, disk monitoring, weather, fan control or notifications. There is no Apple-notarized download yet; build from source. OS changes may affect undocumented read-only sensor interfaces.

The app bundle is approximately 0.3 MB. Short reference runs measured about 0.06%–0.10% of one CPU core while closed and 0.20%–0.37% with visible pages. These development measurements are **not guarantees for every Mac**. Resident memory after opening the UI still needs improvement. See [performance methodology and limitations](docs/performance.md).

## Get started

Requires Apple Command Line Tools (`xcode-select --install`) and an Apple Silicon Mac.

```sh
git clone https://github.com/Jerryx333/tinystat.git
cd tinystat
bash scripts/build.sh
bash scripts/install.sh
open "$HOME/Applications/TinyStat.app"
```

Installs into your personal Applications folder. Quit TinyStat before upgrading. Existing versions are backed up; administrator access is not required. Installation does not quit other monitors or enable login startup.

The menu-bar item starts near the right edge. Command-drag it to rearrange; its position survives restarts. Managers such as Ice can still hide it. See [usage, metric definitions and removal](docs/guide.md).

## Development and contributions

```sh
bash scripts/check.sh       # Build, signature and documentation checks; suitable for CI
bash scripts/verify.sh      # Hardware sensor and sampling checks; requires M1 Max
```

Reproducible bug reports, sensor support and measured performance improvements are welcome. Do not include secrets, complete process lists or screenshots of private windows. Read [contributing](CONTRIBUTING.md).

Planned companion project: [TinyBar](https://github.com/Jerryx333/tinybar), focused on menu-bar item management and currently in the design stage.

License: [Apache-2.0](LICENSE). Copyright 2026 Jerry.
