# Usage and implementation

[Back to README](../README.en.md) | [中文](guide.zh-CN.md)

## Interaction

The menu bar shows CPU usage/temperature and memory usage. Hover or click CPU/GPU/memory readings for a local inspector on the left (right if space is limited). It shows up to two minutes of actual samples, CPU core bars and top processes, or memory categories/swap and top processes. GPU shows only measured usage/temperature, without unsupported process attribution. Moving into the inspector keeps it open; leaving dismisses it without a model request. Send a question from the composer to open a separate chat window. Clicking outside or Escape closes the menu; moving the pointer while editing does not. Drafts and chat survive closing their windows during this app run. Closing chat cancels the current check. Refresh is fixed at 5 seconds with windows closed and 2 seconds while open, with no interval setting or cadence label. Settings control optional login startup and quitting.

## Models

Install a native Codex or Claude Code CLI. Claude default mode requires signing in through its CLI. Claude Code is the initial selection. Select the CLI in Model Settings; an empty executable path searches common install directories and an empty model uses the CLI default. Codex requires an explicit custom provider and does not share terminal login or user config.toml. Configure a custom HTTPS provider, model and key explicitly: Responses-compatible for Codex or Anthropic-compatible for Claude, with x-api-key or Bearer authentication.

Keys live only in the `TinyStat Assistant Provider` Keychain item and are injected into the child environment. An empty key preserves only the key for the same endpoint, CLI and authentication scheme; changing endpoints never reuses another provider’s key. TinyStat does not import Tiller configuration or credentials. Codex uses an isolated temporary directory and explicit provider credentials; it creates no shared login symlink or recovery credential copy. Saving does not test connectivity. Failures appear in chat without disrupting monitoring. The CLI owns its login and may keep provider-specific runtime metadata. Recent CLI versions supporting the restrictive options are required; Claude 2.1.295 was tested locally.

## Evidence and actions

Questions use a separate current-request field, bounded recent conversation, and registered process identities. The assistant can request a fresh overview, local name/PID search (up to 20 returned matches), parent-process inspection, a short CPU/memory observation, or a selected UTF-8 file (8 KiB maximum). A native confirmation lists each batch and the provider receiving its results. Declining or stopping cancels that batch. At most two batches of three checks and three model calls are allowed per question. Ordinary explanations need no fresh telemetry. CPU and memory rankings are partial selections, not a count of all matching processes; parent relationships do not prove application ownership.

Overview refresh sends top eight CPU and memory processes plus a selected focus, coverage, valid swap rates and up to 24 system-history points. System snapshots and discovered identities may be reused within the current conversation, as stated in the grant. File contents and other detailed check results are scoped to the current question. No command arguments, browser tabs, open-file lists or ports are collected. File selection registers only paths and sizes; content requires separate read/upload approval. Model identity distinguishes configured settings from CLI-reported identity; neither independently verifies a provider's actual model.

History stores plain conversation text and receipts locally under `~/Library/Application Support/TinyStat/Conversations` (directory 0700, files 0600). Text may include private user input or model quotations. Raw evidence, file bodies, grants and executable action cards are not archived. At most 30 sessions, 200 messages / 256 KiB per session are retained; capacity errors are explicit, with no automatic deletion. The model receives up to 24 KiB / 24 recent messages; omitted messages are not described as a summary. History supports continue, rename and confirmed permanent deletion of TinyStat's own records. Pages contain 40 messages, with at most 60 live rows. Closing releases rows and check objects. Resuming clears grants, selected files and protection rules, with an explicit notice. No background model calls run.

Actions require a second, separate confirmation. Normal application quit remains available. A conservatively eligible current-user background process may receive SIGTERM (never SIGKILL); this may interrupt work, does not guarantee child shutdown, and does not prevent service restart. Files can be moved to Trash or generated text previewed in full and saved to a new file. Export uses exclusive creation and never overwrites an existing file. Failed partial exports are retained and reported. No arbitrary shell, privileged operations, bulk scanning or permanent deletion of user-selected files is exposed. One short sample cannot prove a leak or per-process GPU attribution.

## Readings and resources

GPU usage is the driver’s `Device Utilization %` sample, not an average over the entire 2/5-second refresh interval. Zero means the driver reported zero for that sample; it does not prove absence of GPU work throughout the interval. Missing values display —.

Whole-machine CPU is normalized to 100%; per-process CPU is 100% per core. Memory is max(0, internal − purgeable) + wired + compressed, displayed as GiB/MiB. Process memory is physical footprint. GPU unified memory must not be counted twice. Memory pressure comes from the OS independently of usage percentage. Temperatures use mapped M1 SMC maxima, excluding HID; M1 Max validation covered 33 CPU and 9 GPU keys. Partial coverage is marked with `*`; missing readings are unknown.

Closed monitoring refreshes every 5 seconds; open windows use 2 seconds. Temperatures follow effective samples. GPU usage follows basic sampling even while closed, keeping up to two minutes of real history; GPU temperature reads occur for the overview or active checks. Startup/unsupported readings remain missing, never invented. Sleep cancels checks and suspends monitoring. Process diagnosis does not modify monitor CPU baselines. CLI requests have a 120-second timeout and 1 MiB output limit; cancellation, timeout and application exit clean up owned process groups. CLI memory and CPU are separate from the app bundle's size.

SMC operations are read-only and never control fans. Preferences use `local.tinystat.app`. See [references](../THIRD_PARTY.md).

## Build and verify

`bash scripts/build.sh` creates an ad-hoc-signed `build/TinyStat.app`. Quit the old instance and use `open build/TinyStat.app` to preview. `bash scripts/install.sh` installs into personal Applications and backs up previous bundles, refusing to replace a running version. Disable login startup before uninstalling. Preferences, backups and Keychain items are not automatically removed.

```sh
bash scripts/check.sh
bash scripts/verify.sh                 # Real M1 Max telemetry and sampling
bash scripts/verify-assistant.sh       # Offline contracts and process cleanup
bash scripts/verify-assistant-live.sh claude # Optional synthetic greeting; uses model quota
```

Hardware coverage is M1 Max / macOS 26.4. Other hardware, older CLIs, login startup, long sleep/resume and multi-display operation still need wider validation. See [performance methodology and historical results](performance.md).


See [assistant security boundaries](assistant-security.md) for native CLI sandbox and authentication limits. Codex requires an explicit custom provider; Claude default login must be completed in its CLI.

## Local process inventory and chat

Open **进程列表** from the overview or chat to browse readable processes locally, search names/PIDs, and sort CPU, memory, thread count or name. Refresh runs every two seconds while open, pauses when minimized or asleep, and releases rows on close. Thread counts are per-process totals, not individual thread utilization. Only an explicitly selected process is added to the usual top CPU/memory evidence when asking the assistant; the full inventory is never automatically uploaded. Normal application quit uses the same local protection, identity checks and confirmation as assistant proposals.

Each request sends fresh evidence, text history and operation receipts. Old evidence objects are not resent; values quoted in prior text remain in history. Evidence is collapsed in the transcript. The latest verified operation receipt stays at the top and also appears in the process window. Chat uses a subdued terminal palette with regular-weight text and increased line spacing.
