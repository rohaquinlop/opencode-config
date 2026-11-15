#!/usr/bin/env bash
# Sandbox tests for install.sh. No network, no writes outside mktemp.
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

run_install() {
  env -u XDG_CONFIG_HOME HOME="$HOME_DIR" bash "$REPO_DIR/install.sh" "$@"
}

snapshot() {
  find "$SANDBOX" -type f -exec "${HASH[@]}" {} + | sort
  find "$SANDBOX" -type l -exec readlink {} + | sort
}

mkdir -p "$LIVE"
printf '{"password":"keep"}\n' >"$LIVE/service.json"
printf '{"theme":{"name":"catppuccin-frappe"}}\n' >"$LIVE/cli.json"

out="$(run_install)"
assert_contains "clean install links files" "$out" "linked AGENTS.md"
assert_eq "a linked file points at the repo" "$(readlink "$LIVE/AGENTS.md")" "$REPO_DIR/config/AGENTS.md"
assert_eq "every tracked repo file is linked" "$(git -C "$REPO_DIR" ls-files -- config | wc -l | tr -d ' ')" "$(find "$LIVE" -type l | wc -l | tr -d ' ')"

before="$(snapshot)"
out="$(run_install)"
assert_eq "a second run prints nothing" "$out" ""
assert_eq "a second run changes nothing" "$(snapshot)" "$before"

rm -f "$LIVE/AGENTS.md"
printf 'live only\n' >"$LIVE/AGENTS.md"
out="$(run_install)"
assert_contains "a real file is replaced by a link" "$out" "linked AGENTS.md"
assert_eq "the link points at the repo" "$(readlink "$LIVE/AGENTS.md")" "$REPO_DIR/config/AGENTS.md"

ln -s "$REPO_DIR/config/commands/gone.md" "$LIVE/commands-gone-link.md"
out="$(run_install)"
assert_contains "a link to a removed repo file is dropped" "$out" "unlinked commands-gone-link.md"
[ -L "$LIVE/commands-gone-link.md" ] && fail "the stale link still exists"

CLONE="$SANDBOX/repo"
CLONE_HOME="$SANDBOX/clone-home"
mkdir -p "$CLONE" "$CLONE_HOME"
git -C "$CLONE" init -q
cp -a "$REPO_DIR/install.sh" "$REPO_DIR/config" "$REPO_DIR/.gitignore" "$CLONE/"
git -C "$CLONE" add -A
git -C "$CLONE" -c user.email=test@example.com -c user.name=test commit -qm init
printf 'machine local\n' >"$CLONE/config/tui.jsonc"
out="$(env -u XDG_CONFIG_HOME HOME="$CLONE_HOME" bash "$CLONE/install.sh")"
[ -L "$CLONE_HOME/.config/opencode/tui.jsonc" ] && fail "an untracked file was linked"
ln -s "$CLONE/config/tui.jsonc" "$CLONE_HOME/.config/opencode/tui.jsonc"
out="$(env -u XDG_CONFIG_HOME HOME="$CLONE_HOME" bash "$CLONE/install.sh")"
assert_contains "a link to an untracked repo file is dropped" "$out" "unlinked tui.jsonc"

SELF="$SANDBOX/self/.config/opencode"
mkdir -p "$SANDBOX/self/.config"
git clone -q "$REPO_DIR" "$SELF"
cp "$REPO_DIR/install.sh" "$SELF/install.sh"
if env -u XDG_CONFIG_HOME HOME="$SANDBOX/self" bash "$SELF/install.sh" >/dev/null 2>&1; then
  fail "install.sh linked a checkout that sits at its own live path"
fi
[ -e "$SELF/config/AGENTS.md" ] || fail "the refused run deleted repo files"

assert_eq "runtime files are left alone" "$(cat "$LIVE/service.json")" '{"password":"keep"}'
assert_eq "runtime preferences are left alone" "$(cat "$LIVE/cli.json")" '{"theme":{"name":"catppuccin-frappe"}}'

printf 'custom\n' >"$SHIM"
run_install >/dev/null
assert_contains "the shim points at the shepherd script" "$(cat "$SHIM")" "plugins/shepherd/scripts/shepherd.sh"
assert_contains "the shim honours XDG_CONFIG_HOME" "$(cat "$SHIM")" "XDG_CONFIG_HOME"

target="$SANDBOX/shim-target"
printf 'target\n' >"$target"
rm -f "$SHIM"
ln -s "$target" "$SHIM"
run_install >/dev/null
assert_eq "the shim is written as a file, not through a symlink" "$(cat "$target")" "target"
[ -L "$SHIM" ] && fail "the shim is still a symlink"

cp "$SHIM" "$SANDBOX/shim-copy"
rm -f "$SHIM"
ln -s "$SANDBOX/shim-copy" "$SHIM"
run_install >/dev/null
[ -L "$SHIM" ] && fail "a matching symlinked shim was left as a link"

if grep -q '"model"' "$REPO_DIR/config/opencode.json"; then
  fail "config/opencode.json still pins a model"
fi
[ -e "$REPO_DIR/config/cli.json" ] && fail "config/cli.json is still shipped"

runtime="$(git -C "$REPO_DIR" ls-files -- config | grep -E '(^|/)(service\.json|auth\.json|cli\.json|tui\.jsonc|opencode\.db.*|herdr|.*\.log|\.env.*)' | grep -Ev '(^|/)\.env\.example$' || true)"
[ -z "$runtime" ] || fail "config/ tracks runtime or secret files: $runtime"

if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES failure(s)" >&2
  exit 1
fi
echo "ok"
