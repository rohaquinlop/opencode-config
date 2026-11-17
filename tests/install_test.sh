#!/usr/bin/env bash
# Sandbox tests for install.sh. Needs GNU stow. No network, no writes outside mktemp.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

HOME_DIR="$SANDBOX/home"
LIVE="$HOME_DIR/.config/opencode"
SHIM="$HOME_DIR/.local/bin/shepherd"
FAILURES=0

if ! command -v stow >/dev/null 2>&1; then
  echo "stow is required for this test" >&2
  exit 1
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

same_yes() {
  if [ "$1" -ef "$2" ]; then
    echo yes
  else
    echo no
  fi
}

run_install() {
  env -u XDG_CONFIG_HOME HOME="$HOME_DIR" bash "$REPO_DIR/install.sh" "$@"
}

if command -v sha256sum >/dev/null 2>&1; then
  HASH=(sha256sum)
else
  HASH=(shasum -a 256)
fi

snapshot() {
  find "$LIVE" -type f -exec "${HASH[@]}" {} + 2>/dev/null | sort
  find "$LIVE" -type l -exec readlink {} + | sort
}

link_count() {
  find "$LIVE" -type l | wc -l | tr -d ' '
}

expected_links() {
  git -C "$REPO_DIR" ls-files -- config | grep -vc '\.stow-local-ignore'
}

mkdir -p "$LIVE"
printf '{"password":"keep"}\n' >"$LIVE/service.json"
printf '{"theme":{"name":"catppuccin-frappe"}}\n' >"$LIVE/cli.json"

out="$(run_install)"
assert_contains "clean install reports work" "$out" "Done."
assert_eq "the live file is the repo file" "$(same_yes "$REPO_DIR/config/AGENTS.md" "$LIVE/AGENTS.md")" "yes"
assert_eq "every tracked file except the stow ignore file is linked" "$(expected_links)" "$(link_count)"

before="$(snapshot)"
out="$(run_install)"
assert_eq "a second run prints nothing" "$out" ""
assert_eq "a second run changes nothing" "$(snapshot)" "$before"

rm -f "$LIVE/commands/jira.md"
cp "$REPO_DIR/config/commands/jira.md" "$LIVE/commands/jira.md"
run_install >/dev/null
assert_eq "an identical copy becomes a link" "$(same_yes "$REPO_DIR/config/commands/jira.md" "$LIVE/commands/jira.md")" "yes"

rm -f "$LIVE/commands/slack.md"
cp "$REPO_DIR/config/commands/slack.md" "$LIVE/commands/slack.md"
rm -f "$LIVE/commands/jira.md"
printf 'mine\n' >"$LIVE/commands/jira.md"
before="$(snapshot)"
if out="$(run_install 2>&1)"; then
  fail "a differing copy should stop the run"
fi
assert_contains "the conflict names the file" "$out" "commands/jira.md"
assert_eq "the differing file is kept" "$(cat "$LIVE/commands/jira.md")" "mine"
assert_eq "the refused run changes nothing" "$(snapshot)" "$before"
[ -L "$LIVE/commands/slack.md" ] && fail "the refused run linked an identical copy"
rm -f "$LIVE/commands/jira.md"
run_install >/dev/null
assert_eq "the identical copy becomes a link" "$(same_yes "$REPO_DIR/config/commands/slack.md" "$LIVE/commands/slack.md")" "yes"

ln -s "$REPO_DIR/config/commands/gone.md" "$LIVE/commands-gone-link.md"
run_install >/dev/null
[ -L "$LIVE/commands-gone-link.md" ] && fail "the stale link still exists"

printf 'custom\n' >"$SHIM"
out="$(run_install)"
assert_contains "a custom shim is replaced" "$out" "installed .local/bin/shepherd"
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

assert_eq "runtime files are left alone" "$(cat "$LIVE/service.json")" '{"password":"keep"}'
assert_eq "runtime preferences are left alone" "$(cat "$LIVE/cli.json")" '{"theme":{"name":"catppuccin-frappe"}}'

CLONE="$SANDBOX/repo"
CLONE_HOME="$SANDBOX/clone-home"
mkdir -p "$CLONE" "$CLONE_HOME"
git -C "$CLONE" init -q
cp -a "$REPO_DIR/install.sh" "$REPO_DIR/config" "$REPO_DIR/.gitignore" "$CLONE/"
git -C "$CLONE" add -A
git -C "$CLONE" -c user.email=test@example.com -c user.name=test commit -qm init
printf 'machine local\n' >"$CLONE/config/tui.jsonc"
env -u XDG_CONFIG_HOME HOME="$CLONE_HOME" bash "$CLONE/install.sh" >/dev/null 2>&1 || true
[ -L "$CLONE_HOME/.config/opencode/tui.jsonc" ] && fail "an ignored runtime file was linked"

SELF="$SANDBOX/self/.config/opencode"
mkdir -p "$SANDBOX/self/.config"
git clone -q "$REPO_DIR" "$SELF"
cp "$REPO_DIR/install.sh" "$SELF/install.sh"
if env -u XDG_CONFIG_HOME HOME="$SANDBOX/self" bash "$SELF/install.sh" >/dev/null 2>&1; then
  fail "install.sh linked a checkout that sits at its own live path"
fi
[ -e "$SELF/config/AGENTS.md" ] || fail "the refused run deleted repo files"

NOGIT="$SANDBOX/nogit"
mkdir -p "$NOGIT"
git -C "$REPO_DIR" archive HEAD | tar -x -C "$NOGIT"
cp "$REPO_DIR/install.sh" "$NOGIT/install.sh"
if env -u XDG_CONFIG_HOME HOME="$NOGIT/home" bash "$NOGIT/install.sh" >/dev/null 2>&1; then
  fail "install.sh ran in a tree that is not a git checkout"
fi

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
