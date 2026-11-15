#!/usr/bin/env bash
# Sandbox tests for install.sh and sync.sh. No network, no writes outside mktemp.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

HOME_DIR="$SANDBOX/home"
STATE_DIR="$SANDBOX/state"
LIVE="$HOME_DIR/.config/opencode"
BACKUP_ROOT="$STATE_DIR/opencode/config-backups"
FAILURES=0

if command -v sha256sum >/dev/null 2>&1; then
  HASH=(sha256sum)
else
  HASH=(shasum -a 256)
fi

fail() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

assert_eq() {
  [ "$2" = "$3" ] || fail "$1: expected [$3], got [$2]"
}

assert_contains() {
  case "$2" in
    *"$3"*) ;;
    *) fail "$1: output does not contain [$3]: ${2:0:400}" ;;
  esac
}

assert_not_contains() {
  case "$2" in
    *"$3"*) fail "$1: output contains [$3]" ;;
  esac
}

file_hash() {
  "${HASH[@]}" "$1" | cut -d' ' -f1
}

tree_hash() {
  local dir
  for dir in "$@"; do
    [ -d "$dir" ] || continue
    (cd "$dir" && find . -type f -exec "${HASH[@]}" {} + | sort)
  done | "${HASH[@]}" | cut -d' ' -f1
}

backup_count() {
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '
}

set_mtime() {
  python3 -c 'import os, sys; t = float(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$1" "$2"
}

run_install() {
  env -u XDG_CONFIG_HOME HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR" bash "$REPO_DIR/install.sh" "$@"
}

mkdir -p "$LIVE"

before="$(tree_hash "$HOME_DIR" "$STATE_DIR")"
out="$(run_install --dry-run)"
assert_contains "dry run reports a missing file" "$out" "would install AGENTS.md"
assert_eq "dry run writes nothing" "$(tree_hash "$HOME_DIR" "$STATE_DIR")" "$before"

out="$(run_install)"
assert_contains "clean install copies files" "$out" "installed AGENTS.md"
assert_eq "clean install leaves no backup" "$(ls -A "$BACKUP_ROOT" 2>/dev/null | wc -l | tr -d ' ')" "0"
assert_eq "clean install matches the repo" "$(file_hash "$LIVE/AGENTS.md")" "$(file_hash "$REPO_DIR/config/AGENTS.md")"

echo "live edit" >>"$LIVE/AGENTS.md"
out="$(run_install)"
assert_contains "plain run reports the skipped file" "$out" "skipped AGENTS.md"
assert_contains "plain run keeps the live edit" "$(cat "$LIVE/AGENTS.md")" "live edit"
assert_eq "plain run leaves no backup" "$(ls -A "$BACKUP_ROOT" 2>/dev/null | wc -l | tr -d ' ')" "0"

before="$(tree_hash "$HOME_DIR" "$STATE_DIR")"
out="$(run_install --dry-run)"
assert_contains "dry run mirrors the default action" "$out" "would skip AGENTS.md"
assert_eq "dry run keeps the tree" "$(tree_hash "$HOME_DIR" "$STATE_DIR")" "$before"

out="$(run_install --dry-run --force)"
assert_contains "forced dry run lists the replacement" "$out" "would replace AGENTS.md"
assert_eq "forced dry run keeps the tree" "$(tree_hash "$HOME_DIR" "$STATE_DIR")" "$before"

out="$(run_install --force)"
assert_contains "force replaces the file" "$out" "replaced AGENTS.md"
assert_eq "force restores the repo copy" "$(file_hash "$LIVE/AGENTS.md")" "$(file_hash "$REPO_DIR/config/AGENTS.md")"
assert_eq "force makes one backup dir" "$(backup_count)" "1"
assert_contains "backup holds the replaced file" "$(find "$BACKUP_ROOT" -name AGENTS.md -exec cat {} +)" "live edit"

for i in 1 2 3 4 5 6 7; do
  mkdir -p "$BACKUP_ROOT/seed-$i"
  set_mtime "$BACKUP_ROOT/seed-$i" "$((1000000000 + i * 3600))"
done
echo "another edit" >>"$LIVE/AGENTS.md"
run_install --force >/dev/null
assert_eq "old backups are pruned" "$(backup_count)" "5"
newest="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name 'seed-*' | sort | tail -1)"
assert_contains "the newest backup holds the latest edit" "$(find "$newest" -name AGENTS.md -exec cat {} +)" "another edit"

rm -f "$LIVE/AGENTS.md"
ln -s "$REPO_DIR/config/AGENTS.md" "$LIVE/AGENTS.md"
out="$(run_install)"
assert_not_contains "a matching symlink is left alone" "$out" "skipped AGENTS.md"
assert_not_contains "a matching symlink makes no backup" "$out" "replaced AGENTS.md"
[ -L "$LIVE/AGENTS.md" ] || fail "the matching symlink was replaced"
assert_eq "the run with a symlink adds no backup" "$(backup_count)" "5"

printf 'custom\n' >"$HOME_DIR/.local/bin/shepherd"
out="$(run_install)"
assert_contains "plain run skips a custom shim" "$out" "skipped .local/bin/shepherd"
assert_eq "custom shim is kept" "$(cat "$HOME_DIR/.local/bin/shepherd")" "custom"
run_install --force >/dev/null
assert_contains "force replaces the shim" "$(cat "$HOME_DIR/.local/bin/shepherd")" "plugins/shepherd/scripts/shepherd.sh"

if grep -q '"model"' "$REPO_DIR/config/opencode.json"; then
  fail "config/opencode.json still pins a model"
fi
[ -e "$REPO_DIR/config/cli.json" ] && fail "config/cli.json is still shipped"

SYNC_LIVE="$SANDBOX/sync-live"
SYNC_DEST="$SANDBOX/sync-dest"
mkdir -p "$SYNC_LIVE"
printf '{\n  "$schema": "https://opencode.ai/config.json",\n  "model": "x/y",\n  "update": "disable"\n}\n' >"$SYNC_LIVE/opencode.json"
printf '{\n  "theme": {\n    "name": "system"\n  }\n}\n' >"$SYNC_LIVE/cli.json"
SYNC_SRC="$SYNC_LIVE" SYNC_DEST="$SYNC_DEST" bash "$REPO_DIR/sync.sh" >/dev/null
grep -q '"model"' "$SYNC_DEST/opencode.json" && fail "sync captured the model pin"
grep -q '"update"' "$SYNC_DEST/opencode.json" || fail "sync dropped the rest of opencode.json"
[ -e "$SYNC_DEST/cli.json" ] && fail "sync captured cli.json"

if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES failure(s)" >&2
  exit 1
fi
echo "ok"
