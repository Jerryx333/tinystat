# Contributing

Small, reproducible improvements are welcome. Open an issue describing the problem, macOS version, chip family, reproduction steps and expected behavior. Redact private process names, paths, screenshots and credentials.

- Build/documentation gate: `bash scripts/check.sh`.
- Real M1 Max verification: `bash scripts/verify.sh`.
- Performance changes: compare equivalent closed and visible scenarios with `bash scripts/benchmark.sh 300`; state hardware, duration and measurement limitations.
- New sensor mappings need evidence of component identity and real hardware reads; missing data must stay unavailable, not become zero.
- Preserve read-only hardware access, demand-based sampling and bounded history. No new network access, helpers, runtime dependencies or startup changes without prior discussion.
- Keep local reports, app binaries and personal environment notes out of commits. Use Conventional Commit subjects.

CI builds and checks public documentation; it does not claim hardware sensors, login startup, performance or multi-display behavior were exercised. The interface is currently in Chinese; documentation is bilingual, and UI localization remains future work.
