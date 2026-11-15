#!/usr/bin/env bash
# Link this repository's config/ tree into the live OpenCode config dir.
#
# Every live file becomes a symlink to its repo counterpart, the way a dotfiles
# checkout works: an edit made live lands in the repo, and git shows it. Files
# that OpenCode writes itself (cli.json, service.json, theme, model) are not in
# config/, so they stay real files and are never touched.
#
# A file removed from config/ loses its link on the next run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/config"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
SHIM="$HOME/.local/bin/shepherd"
SHIM_BODY='#!/usr/bin/env bash
exec bash "$HOME/.config/opencode/plugins/shepherd/scripts/shepherd.sh" "$@"'

tmp=""
changes=0

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

  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    continue
  fi
  if [ -d "$dest" ] && [ ! -L "$dest" ]; then
    echo "skipped $rel (a directory is in the way)" >&2
    continue
  fi

  mkdir -p "$(dirname "$dest")"
  rm -f "$dest"
  ln -s "$src" "$dest"
  echo "linked $rel"
  changes=$((changes + 1))
done < <(find "$SRC" -type f -print0)

while IFS= read -r -d '' dest; do
  target="$(readlink "$dest")"
  case "$target" in
    "$SRC"/*)
      if [ ! -e "$target" ]; then
        rm -f "$dest"
        echo "unlinked ${dest#"$DEST"/}"
        changes=$((changes + 1))
      fi
      ;;
  esac
done < <(find "$DEST" -type l -print0)

if [ ! -f "$SHIM" ] || [ "$(cat "$SHIM")" != "$SHIM_BODY" ]; then
  mkdir -p "$(dirname "$SHIM")"
  tmp="$SHIM.tmp.$$"
  printf '%s\n' "$SHIM_BODY" >"$tmp"
  chmod +x "$tmp"
  mv -f "$tmp" "$SHIM"
  tmp=""
  echo "installed .local/bin/shepherd"
  changes=$((changes + 1))
fi

if [ "$changes" -gt 0 ]; then
  echo "Done. Start a new OpenCode session, or run /reload."
fi
