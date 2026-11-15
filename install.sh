#!/usr/bin/env bash
# Link this repository's config/ tree into the live OpenCode config dir.
#
# Every live file becomes a symlink to its repo counterpart, the way a dotfiles
# checkout works: an edit made live lands in the repo, and git shows it. Only
# tracked files are linked. Files that OpenCode writes itself (cli.json,
# service.json, theme, model) are never tracked, so they stay real files.
#
# A file removed from the index loses its link on the next run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/config"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
SHIM="$HOME/.local/bin/shepherd"
SHIM_BODY='#!/usr/bin/env bash
exec bash "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins/shepherd/scripts/shepherd.sh" "$@"'

tmp=""
changes=0

cleanup() {
  if [ -n "$tmp" ]; then
    rm -f "$tmp"
  fi
}
trap cleanup EXIT

mkdir -p "$DEST"

tracked() {
  git -C "$REPO_DIR" ls-files --error-unmatch -- "$1" >/dev/null 2>&1
}

while IFS= read -r -d '' rel; do
  src="$REPO_DIR/$rel"
  dest="$DEST/${rel#config/}"

  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    continue
  fi
  if [ -d "$dest" ] && [ ! -L "$dest" ]; then
    echo "skipped ${rel#config/} (a directory is in the way)" >&2
    continue
  fi

  mkdir -p "$(dirname "$dest")"
  rm -f "$dest"
  ln -s "$src" "$dest"
  echo "linked ${rel#config/}"
  changes=$((changes + 1))
done < <(git -C "$REPO_DIR" ls-files -z -- config)

while IFS= read -r -d '' dest; do
  target="$(readlink "$dest")"
  case "$target" in
    "$REPO_DIR"/config/*)
      if ! tracked "${target#"$REPO_DIR"/}"; then
        rm -f "$dest"
        echo "unlinked ${dest#"$DEST"/}"
        changes=$((changes + 1))
      fi
      ;;
  esac
done < <(find "$DEST" -type l -print0)

if [ -L "$SHIM" ] || [ ! -f "$SHIM" ] || [ "$(cat "$SHIM")" != "$SHIM_BODY" ]; then
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
