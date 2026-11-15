#!/usr/bin/env bash
# Mirror this repository's config/ tree into the live OpenCode config dir.
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
  rm -f "$dest"
  mv -f "$tmp" "$dest"
  echo "installed $rel"
done < <(find "$SRC" -type f -print0)

if [ ! -f "$SHIM" ] || [ "$(cat "$SHIM")" != "$SHIM_BODY" ]; then
  mkdir -p "$(dirname "$SHIM")"
  rm -f "$SHIM"
  printf '%s\n' "$SHIM_BODY" >"$SHIM"
  chmod +x "$SHIM"
  echo "installed .local/bin/shepherd"
fi

echo "Done. Start a new OpenCode session, or run /reload."
