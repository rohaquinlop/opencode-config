#!/usr/bin/env bash
# Copy this repository's config/ tree into the live OpenCode config dir.
#
# Missing files are installed. Files that differ are skipped unless --force is
# given, because OpenCode writes some of them at runtime (theme, verbosity).
# Forced replacements go to a backup tree under XDG_STATE_HOME; the last five
# are kept.
#
# To capture changes made in the live config back into this repo, run
# ./sync.sh.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: install.sh [--force] [--dry-run]

  (no flag)  install missing files, skip files that differ
  --force    replace files that differ, after backing them up
  --dry-run  print what would happen, change nothing
EOF
}

force=0
dry_run=0
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    --dry-run) dry_run=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/config"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/opencode/config-backups"
BACKUP="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
KEEP_BACKUPS=5
SHIM="$HOME/.local/bin/shepherd"
SHIM_BODY='#!/usr/bin/env bash
exec bash "$HOME/.config/opencode/plugins/shepherd/scripts/shepherd.sh" "$@"'

backup() {
  local dest="$1"
  local rel="${dest#"$DEST"/}"
  mkdir -p "$(dirname "$BACKUP/$rel")"
  cp -a "$dest" "$BACKUP/$rel"
}

prune_backups() {
  [ -d "$BACKUP_ROOT" ] || return 0
  ls -1dt "$BACKUP_ROOT"/*/ 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | while IFS= read -r old; do
    rm -rf "$old"
  done
}

skipped=0

if [ "$dry_run" -eq 0 ]; then
  mkdir -p "$DEST"
fi

while IFS= read -r -d '' src; do
  rel="${src#"$SRC"/}"
  dest="$DEST/$rel"

  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    if [ "$dry_run" -eq 1 ]; then
      echo "would install $rel"
    else
      mkdir -p "$(dirname "$dest")"
      cp -p "$src" "$dest"
      echo "installed $rel"
    fi
    continue
  fi

  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    continue
  fi

  if [ "$dry_run" -eq 1 ]; then
    if [ "$force" -eq 1 ]; then
      echo "would replace $rel"
    else
      echo "would skip $rel (differs, use --force)"
    fi
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$force" -eq 0 ]; then
    echo "skipped $rel (differs, use --force)"
    skipped=$((skipped + 1))
    continue
  fi

  mkdir -p "$(dirname "$dest")"
  backup "$dest"
  rm -f "$dest"
  cp -p "$src" "$dest"
  echo "replaced $rel"
done < <(find "$SRC" -type f -print0)

if [ ! -f "$SHIM" ] || [ "$(cat "$SHIM")" != "$SHIM_BODY" ]; then
  if [ "$dry_run" -eq 1 ]; then
    echo "would install .local/bin/shepherd"
  else
    mkdir -p "$HOME/.local/bin"
    printf '%s\n' "$SHIM_BODY" >"$SHIM"
    chmod +x "$SHIM"
    echo "installed .local/bin/shepherd"
  fi
fi

if [ -d "$BACKUP" ]; then
  prune_backups
  echo "Backups: $BACKUP (keeping the last $KEEP_BACKUPS)"
fi

if [ "$skipped" -gt 0 ]; then
  if [ "$dry_run" -eq 1 ]; then
    if [ "$force" -eq 1 ]; then
      echo "Dry run: $skipped file(s) would be replaced. Nothing changed."
    else
      echo "Dry run: $skipped file(s) would be skipped. Nothing changed."
    fi
  else
    echo "$skipped file(s) differ. Re-run with --force to replace them."
  fi
fi

if [ "$dry_run" -eq 0 ]; then
  echo "Done. Start a new OpenCode session, or run /reload."
fi
