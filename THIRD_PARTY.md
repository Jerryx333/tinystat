# Third-party references

TinyStat links only Apple system frameworks and does not vendor third-party libraries, assets or runtime binaries.

The M1 sensor key list was taken from, and the AppleSMC packet layout cross-checked against, the MIT-licensed [Stats](https://github.com/exelban/stats) project:

- [SMC definitions](https://github.com/exelban/stats/blob/master/SMC/smc.swift)
- [Sensor key mappings](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift)
- [Stats license](https://github.com/exelban/stats/blob/master/LICENSE); a copy is retained in [licenses/Stats-MIT.txt](licenses/Stats-MIT.txt).

The C telemetry reader was independently written. No Stats implementation, artwork or binary is distributed in this repository. If future contributions incorporate third-party implementation code, preserve its copyright and license notices and update this file.

iStat Menus, Ice, Apple and macOS are names of their respective projects or owners. TinyStat is independent and is not affiliated with or endorsed by them.
