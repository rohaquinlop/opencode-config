#!/usr/bin/env bash
# Stow this repository's config/ package into the live OpenCode config dir.
#
# GNU stow links every file in config/ into ~/.config/opencode, the same way a
# dotfiles checkout works: an edit made live lands in the repo, and git shows
# it. Files that OpenCode writes itself (cli.json, service.json, theme, model)
# are ignored, so they stay real files.
#
# A file removed from config/ loses its link on the next run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/config"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
SHIM="$HOME/.local/bin/shepherd"
SHIM_BODY='#!/usr/bin/env bash
exec bash "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins/shepherd/scripts/shepherd.sh" "$@"'
IGNORES=(cli.json service.json tui.jsonc '\.log' '\.env')

if ! command -v stow >/dev/null 2>&1; then
  echo "install.sh: GNU stow is required (pacman -S stow)" >&2
  exit 1
fi

toplevel="$(git -C "$REPO_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$toplevel" ] || [ "$(cd "$toplevel" && pwd -P)" != "$(cd "$REPO_DIR" && pwd -P)" ]; then
  echo "install.sh: $REPO_DIR is not the root of a git checkout" >&2
  exit 1
fi

tmp=""
changes=0

cleanup() {
  if [ -n "$tmp" ]; then
    rm -f "$tmp"
  fi
}
trap cleanup EXIT

mkdir -p "$DEST"

if [ -L "$DEST" ]; then
  echo "install.sh: $DEST is a symlink; link a real directory instead" >&2
  exit 1
fi

dest_real="$(cd "$DEST" && pwd -P)"
repo_real="$(cd "$REPO_DIR" && pwd -P)"
case "$dest_real/" in
  "$repo_real"/*)
    echo "install.sh: $DEST is inside $REPO_DIR; refusing to link a tree into itself" >&2
    exit 1
    ;;
esac

# Copied files from an older install are replaced by links; a file that differs
# from the repo is reported, not overwritten.
conflicts=0
while IFS= read -r rel; do
  src="$REPO_DIR/$rel"
  dest="$DEST/${rel#config/}"

  [ -L "$dest" ] && continue
  [ -e "$dest" ] || continue

  if cmp -s "$src" "$dest"; then
    rm -f "$dest"
    changes=$((changes + 1))
  else
    echo "install.sh: $dest differs from $rel" >&2
    conflicts=$((conflicts + 1))
  fi
done < <(git -C "$REPO_DIR" ls-files -- config)

if [ "$conflicts" -gt 0 ]; then
  echo "Move your change into config/ (or revert it) and re-run." >&2
  exit 1
fi

ignore_args=()
for pattern in "${IGNORES[@]}"; do
  ignore_args+=("--ignore=$pattern")
done

links_before="$(find "$DEST" -type l | wc -l | tr -d ' ')"
stow --dir "$REPO_DIR" --target "$DEST" --restow --no-folding "${ignore_args[@]}" config

# stow leaves a dangling link behind when its repo file is gone.
while IFS= read -r -d '' link; do
  target="$(readlink -m "$link")"
  case "$target" in
    "$SRC"/*)
      if [ ! -e "$target" ]; then
        rm -f "$link"
        echo "unlinked ${link#"$DEST"/}"
        changes=$((changes + 1))
      fi
      ;;
  esac
done < <(find "$DEST" -type l -print0)

links_after="$(find "$DEST" -type l | wc -l | tr -d ' ')"
if [ "$links_before" != "$links_after" ]; then
  changes=$((changes + 1))
fi

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
