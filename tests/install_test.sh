#!/usr/bin/env bash
# Sandbox tests for install.sh. No network, no writes outside mktemp.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

HOME_DIR="$SANDBOX/home"
STATE_DIR="$SANDBOX/state"
LIVE="$HOME_DIR/.config/opencode"
BACKUP_ROOT="$STATE_DIR/opencode/config-backups"
FAILURES=0

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
    *) fail "$1: output does not contain [$3]: $2" ;;
  esac
}

run_install() {
  env -u XDG_CONFIG_HOME HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR" bash "$REPO_DIR/install.sh" "$@"
}

tree_hash() {
  (cd "$1" && find . -type f -exec sha256sum {} + | sort | sha256sum)
}

backup_count() {
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '
}

mkdir -p "$LIVE"

out="$(run_install)"
assert_contains "clean install copies files" "$out" "installed AGENTS.md"
assert_eq "clean install leaves no backup" "$(ls -A "$BACKUP_ROOT" 2>/dev/null | wc -l | tr -d ' ')" "0"
assert_eq "clean install matches the repo" "$(sha256sum "$LIVE/AGENTS.md" | cut -d' ' -f1)" "$(sha256sum "$REPO_DIR/config/AGENTS.md" | cut -d' ' -f1)"

echo "live edit" >>"$LIVE/AGENTS.md"
out="$(run_install)"
assert_contains "plain run reports the skipped file" "$out" "skipped AGENTS.md"
assert_contains "plain run keeps the live edit" "$(cat "$LIVE/AGENTS.md")" "live edit"
assert_eq "plain run leaves no backup" "$(ls -A "$BACKUP_ROOT" 2>/dev/null | wc -l | tr -d ' ')" "0"

before="$(tree_hash "$HOME_DIR")"
out="$(run_install --dry-run)"
assert_contains "dry run lists the file" "$out" "would replace AGENTS.md"
assert_eq "dry run writes nothing" "$(tree_hash "$HOME_DIR")" "$before"

out="$(run_install --force)"
assert_contains "force replaces the file" "$out" "replaced AGENTS.md"
assert_eq "force restores the repo copy" "$(sha256sum "$LIVE/AGENTS.md" | cut -d' ' -f1)" "$(sha256sum "$REPO_DIR/config/AGENTS.md" | cut -d' ' -f1)"
assert_eq "force makes one backup dir" "$(backup_count)" "1"
assert_contains "backup holds the replaced file" "$(find "$BACKUP_ROOT" -name AGENTS.md -exec cat {} +)" "live edit"

for i in 1 2 3 4 5 6 7; do
  mkdir -p "$BACKUP_ROOT/seed-$i"
  touch -d "-$i hour" "$BACKUP_ROOT/seed-$i"
done
echo "another edit" >>"$LIVE/AGENTS.md"
run_install --force >/dev/null
assert_eq "old backups are pruned" "$(backup_count)" "5"
assert_eq "the newest backup survives" "$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name 'seed-*' | wc -l | tr -d ' ')" "1"

if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES failure(s)" >&2
  exit 1
fi
echo "ok"
