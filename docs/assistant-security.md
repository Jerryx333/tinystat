# Assistant security boundary

TinyStat treats process names, file names, diagnostic data, previous model answers and model proposals as untrusted. Prompt instructions improve answers but are not authorization.

## Local execution

The model receives no shell, file, browser or MCP tools. It can return explanation text and up to five typed proposals. Only targets registered for the current request are eligible. The native application displays identity and impact, defaults confirmation to Cancel, checks identity again, then requests normal application termination or moves a user-selected ordinary file to Trash. It never permanently deletes, force-kills, or executes model-generated commands. Model replies render as plain native text.

“保留此应用 / 保留此文件” creates a local conversation rule. Protected bundles remain protected after process restart; protected file paths remain protected after reselection. Models cannot clear these rules. Starting a new conversation explicitly resets them. Natural-language preferences alone are not a local protection rule; use the protection button to lock the decision.

## CLI process sandbox

Every request launches a native Mach-O CLI inside macOS Seatbelt using `/usr/bin/sandbox-exec`, with a default-deny profile inherited by descendants. Failure does not retry without a sandbox. Shell/Node wrappers are rejected; select the installed native executable. The sandbox permits its executable, system runtime/configuration files, and a private per-request scratch directory. It permits global file metadata queries (which can reveal existence) but not arbitrary file contents. Only the scratch directory is writable through filesystem operations.

Default login adds narrowly named CLI login/config files and, for Claude, Keychain services and the login Keychain directory. Keychain service access is not restricted to an individual entry by Seatbelt: system ACLs remain the boundary. Because `/usr/bin/security` is executable in this mode, Keychain entries whose ACL trusts it are potentially accessible, not just the Claude login. This mode can execute `/usr/bin/security`, `/bin/sh` and `/bin/bash`: Claude 2.1.295 required a shell-mediated authentication subprocess in testing on macOS 26.4, where `/private/var/select/sh` points to `/bin/bash`. Selecting dash or zsh instead is not supported by this profile. Shell descendants inherit the same filesystem/network sandbox. This is a CLI runtime exception, not a model shell tool. The custom-provider and Codex profiles deny those shell/security executables and Keychain service access. Authentication may fail when a CLI requires a blocked refresh/write; OAuth token refresh and persistence have not been verified. TinyStat does not extract another application's credentials or silently relax the policy. Codex requires an explicitly configured custom provider. Its default shared-login path is disabled because read-only token refresh could invalidate the terminal login. TinyStat no longer creates LoginRecovery copies.

Remote outbound IP connections are allowed for configured providers, DNS and TLS; this is **not** a destination-domain firewall. Inbound networking and arbitrary Unix sockets are denied. The Seatbelt `localhost` filter blocks 127.0.0.1 and ::1 except an explicitly configured local provider's port. It does not reliably cover all address aliases (127.0.0.2 and ::ffff:127.0.0.1 were observed allowed), local network interfaces or LAN services; this is not complete local-network isolation. Local proxies and tools needing additional services are not implicitly allowed. `sandbox-exec` is a deprecated macOS facility, so future system/CLI versions require revalidation; this is not an App Store App Sandbox entitlement.

The native monitoring application and typed action executor are outside the CLI sandbox. The sandbox does not guarantee truthful model answers, prevent persuasion into a bad confirmed action, or eliminate the file-path replacement race between validation and Trash. These limits must not be described as injection immunity.

## Reproducible verification

- `bash scripts/check.sh`: build/signature, local contracts, input handling, sandbox probes, documentation.
- `python3 scripts/verify-sandbox.py --native-cli`: additionally require and verify installed native Claude/Codex startup; this local prerequisite is not required by CI.
- `python3 tests/cli-isolation.py`: real CLI requests to a synthetic local server, tool/global-rule/hook isolation.
- `python3 tests/codex-success.py`: real native Codex inside the production sandbox, synthetic Responses SSE and product parser.
- `bash scripts/verify-assistant-live.sh claude`: optional synthetic remote greeting using the CLI's own login; no machine telemetry.

Sandbox probes verify outside read/write denial, shell execution denial in non-login profiles and shell startup and inherited file/exec restrictions in Claude login mode, localhost denial and scratch write access, plus native Claude/Codex startup. The live synthetic request separately verifies Claude authentication and the production response parser. These checks do not establish every possible escape or all provider authentication paths.
