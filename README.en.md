# TinyStat

[中文](README.md) | [English](README.en.md)

CPU, GPU, memory and temperatures in a small native macOS menu-bar monitor.

## Why it exists

TinyStat keeps CPU, GPU, memory and temperatures visible. Ask why a reading is high: the assistant receives a dated snapshot and the leading processes, explains the evidence, and lets you decide what to handle.

- Three passive metric cards. Sending a question opens a separate chat window that survives closing the menu.
- Expand each check to inspect processes, timestamps and coverage; observations stay separate from inferences and unknowns.
- Connect a local Codex / Claude Code CLI or configure a compatible provider; API keys stay in Keychain.
- Confirm action cards to request a normal application quit or move a user-selected regular file to Trash. Receipts and fresh checks follow.
- No model calls until you ask. Native Swift + AppKit; GPU usage history retained continuously, temperatures on demand, fixed 5-second closed and 2-second open refresh.

## Current status

**Early usable version with limited compatibility coverage.** Targets Apple Silicon and macOS 13+. Hardware validation covers only M1 Max on macOS 26.4; earlier OS versions are deployment targets, not verified runtime support. The UI is currently Chinese-only; temperatures use the maximum valid mapped M1 SMC reading, excluding HID; 33 CPU and 9 GPU keys were verified on M1 Max, with missing keys marked `*`. Other chips show temperatures as unavailable instead of guessing sensor identities.

This is not a complete iStat Menus replacement: no network speed, disk monitoring, weather, fan control or notifications. There is no Apple-notarized download yet; build from source. OS changes may affect undocumented read-only sensor interfaces.

The app bundle is approximately 0.5 MB, excluding external agent CLIs. Historical monitor benchmarks do not measure chat costs. Model requests launch a temporary CLI process group that is cleaned up on completion or cancellation. See [performance methodology and historical results](docs/performance.md).

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
bash scripts/verify-assistant.sh # Offline assistant and action-boundary checks
```

Reproducible bug reports, sensor support and measured performance improvements are welcome. Do not include secrets, complete process lists or screenshots of private windows. Read [contributing](CONTRIBUTING.md).

Planned companion project: [TinyBar](https://github.com/Jerryx333/tinybar), focused on menu-bar item management and currently in the design stage.

License: [Apache-2.0](LICENSE). Copyright 2026 Jerry.
