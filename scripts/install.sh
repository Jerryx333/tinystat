#!/bin/bash
# Install locally with backup; run: bash scripts/install.sh
# Requires a built app; no administrator rights or startup changes.
set -euo pipefail
cd "$(dirname "$0")/.."
dest="$HOME/Applications/TinyStat.app"
codesign --verify --strict build/TinyStat.app
mkdir -p "$HOME/Applications"
if [[ -e "$dest" ]] && diff -qr build/TinyStat.app "$dest" >/dev/null; then
  printf 'Already installed: %s\n' "$dest"; exit 0
fi
if pgrep -x TinyStat >/dev/null; then echo 'Quit TinyStat before upgrading.' >&2; exit 1; fi
stage="$(mktemp -d "$HOME/Applications/.tinystat-stage.XXXXXX")"
cleanup() {
  if ! rmdir "$stage" 2>/dev/null; then printf 'Staged files retained: %s\n' "$stage" >&2; fi
}
trap cleanup EXIT
ditto build/TinyStat.app "$stage/TinyStat.app"
codesign --verify --strict "$stage/TinyStat.app"
backup=""
if [[ -e "$dest" ]]; then
  backupRoot="$HOME/Library/Application Support/TinyStat/Backups"
  mkdir -p "$backupRoot"
  backup="$backupRoot/TinyStat.$(date -u +%Y%m%dT%H%M%SZ).zip"
  [[ ! -e "$backup" ]] || { echo 'Backup already exists; retry later.' >&2; exit 1; }
  ditto -c -k --keepParent "$dest" "$backup"
  mv "$dest" "$stage/previous.app"
fi
if ! mv "$stage/TinyStat.app" "$dest"; then
  if [[ -e "$stage/previous.app" ]]; then mv "$stage/previous.app" "$dest"; fi
  echo "Installation failed; staged files kept at $stage" >&2; exit 1
fi
if [[ -e "$stage/previous.app" ]]; then
  # Keep the old bundle out of LaunchServices discovery; zip backup is already verified by ditto.
  retained="$(mktemp -d "$backupRoot/retained.XXXXXX")"
  mv "$stage/previous.app" "$retained/previous.bundle"
  printf 'Previous bundle retained: %s/previous.bundle; zip: %s\n' "$retained" "$backup"
fi
printf 'Installed: %s\n' "$dest"
