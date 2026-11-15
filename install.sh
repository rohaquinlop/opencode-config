#!/usr/bin/env bash
# Copy this repository's config/ tree into the live OpenCode config dir.
#
# The repo owns these files: a live copy that differs is replaced. Runtime state
# that OpenCode writes itself (theme, verbosity, model) is not shipped, so it
# survives a run.
#
# To capture changes made in the live config back into this repo, run
# ./sync.sh.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/config"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
SHIM="$HOME/.local/bin/shepherd"
SHIM_BODY='#!/usr/bin/env bash
exec bash "$HOME/.config/opencode/plugins/shepherd/scripts/shepherd.sh" "$@"'

tmp=""
installed=0

cleanup() {
  if [ -n "$tmp" ]; then
    rm -f "$tmp"
  fi
}
trap cleanup EXIT

mkdir -p "$DEST"

while IFS= read -r -d '' src; do
  rel="${src#"$SRC"/}"
  dest="$DEST/$rel"

  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    continue
  fi

  mkdir -p "$(dirname "$dest")"
  tmp="$dest.tmp.$$"
  cp -p "$src" "$tmp"
  mv -f "$tmp" "$dest"
  tmp=""
  echo "installed $rel"
  installed=$((installed + 1))
done < <(find "$SRC" -type f -print0)

if [ ! -f "$SHIM" ] || [ "$(cat "$SHIM")" != "$SHIM_BODY" ]; then
  mkdir -p "$(dirname "$SHIM")"
  tmp="$SHIM.tmp.$$"
  printf '%s\n' "$SHIM_BODY" >"$tmp"
  chmod +x "$tmp"
  mv -f "$tmp" "$SHIM"
  tmp=""
  echo "installed .local/bin/shepherd"
  installed=$((installed + 1))
fi

if [ "$installed" -gt 0 ]; then
  echo "Done. Start a new OpenCode session, or run /reload."
fi
