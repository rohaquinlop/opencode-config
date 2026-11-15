#!/usr/bin/env bash
# Sandbox tests for install.sh and sync.sh. No network, no writes outside mktemp.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

HOME_DIR="$SANDBOX/home"
LIVE="$HOME_DIR/.config/opencode"
SHIM="$HOME_DIR/.local/bin/shepherd"
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
  (cd "$1" && find . -type f -exec "${HASH[@]}" {} + | sort) | "${HASH[@]}" | cut -d' ' -f1
}

run_install() {
  env -u XDG_CONFIG_HOME HOME="$HOME_DIR" bash "$REPO_DIR/install.sh" "$@"
}

mkdir -p "$LIVE"

out="$(run_install)"
assert_contains "clean install copies files" "$out" "installed AGENTS.md"
assert_eq "clean install matches the repo" "$(file_hash "$LIVE/AGENTS.md")" "$(file_hash "$REPO_DIR/config/AGENTS.md")"
assert_eq "clean install writes nothing outside the config dir and the shim" "$(find "$SANDBOX" -mindepth 1 -maxdepth 3 -type d | sort | tr '\n' ' ')" "$(printf '%s ' "$SANDBOX/home" "$HOME_DIR/.config" "$LIVE" "$HOME_DIR/.local" "$HOME_DIR/.local/bin")"

before="$(tree_hash "$SANDBOX")"
out="$(run_install)"
assert_not_contains "a second run installs nothing" "$out" "installed"
assert_eq "a second run changes nothing" "$(tree_hash "$SANDBOX")" "$before"

echo "live edit" >>"$LIVE/AGENTS.md"
out="$(run_install)"
assert_contains "a live edit is replaced" "$out" "installed AGENTS.md"
assert_eq "the repo copy wins" "$(file_hash "$LIVE/AGENTS.md")" "$(file_hash "$REPO_DIR/config/AGENTS.md")"

printf 'custom\n' >"$SHIM"
out="$(run_install)"
assert_contains "a custom shim is replaced" "$out" "installed .local/bin/shepherd"
assert_contains "the shim points at the shepherd script" "$(cat "$SHIM")" "plugins/shepherd/scripts/shepherd.sh"

target="$SANDBOX/shim-target"
printf 'target\n' >"$target"
rm -f "$SHIM"
ln -s "$target" "$SHIM"
run_install >/dev/null
assert_eq "the shim is written as a file, not through a symlink" "$(cat "$target")" "target"
[ -L "$SHIM" ] && fail "the shim is still a symlink"

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
