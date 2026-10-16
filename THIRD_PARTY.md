# Third-party references

TinyStat links only Apple system frameworks and does not vendor third-party libraries, assets or runtime binaries.

The M1 sensor key list was taken from, and the AppleSMC packet layout cross-checked against, the MIT-licensed [Stats](https://github.com/exelban/stats) project:

- [SMC definitions](https://github.com/exelban/stats/blob/master/SMC/smc.swift)
- [Sensor key mappings](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift)
- [Stats license](https://github.com/exelban/stats/blob/master/LICENSE); a copy is retained in [licenses/Stats-MIT.txt](licenses/Stats-MIT.txt).

The C telemetry reader was independently written. No Stats implementation, artwork or binary is distributed in this repository. If future contributions incorporate third-party implementation code, preserve its copyright and license notices and update this file.

iStat Menus, Ice, Apple and macOS are names of their respective projects or owners. TinyStat is independent and is not affiliated with or endorsed by them.

The assistant integration was designed after inspecting the local Tiller project's CLI/provider pattern. TinyStat's process supervision, diagnostics, action validation and AppKit UI were implemented here; no Tiller implementation or external CLI binary is bundled. Installed Codex and Claude Code remain separate dependencies governed by their own terms. OpenAI CLI options were checked against [App Server](https://developers.openai.com/codex/app-server) and [configuration reference](https://developers.openai.com/codex/config-reference), then verified with local synthetic endpoints.
