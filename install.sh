#!/usr/bin/env bash
# Copy this repository's config/ tree into ~/.config/opencode.
#
# Existing files are moved to ~/.opencode-config-backup-<timestamp>/ first.
# Nothing is deleted. Safe to re-run: identical files are skipped.
#
# To capture changes made in the live config back into this repo, run
# ./sync.sh.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/config"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
BACKUP="$HOME/opencode-config-backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$DEST"

backup() {
  local dest="$1"
  local rel="${dest#"$DEST"/}"
  mkdir -p "$(dirname "$BACKUP/$rel")"
  cp -a "$dest" "$BACKUP/$rel"
}

while IFS= read -r -d '' src; do
  rel="${src#"$SRC"/}"
  dest="$DEST/$rel"
  mkdir -p "$(dirname "$dest")"

  if [ -L "$dest" ]; then
    backup "$dest"
    rm -f "$dest"
  elif [ -e "$dest" ] && cmp -s "$src" "$dest"; then
    continue
  elif [ -e "$dest" ]; then
    backup "$dest"
    rm -f "$dest"
  fi

  cp -p "$src" "$dest"
  echo "installed $rel"
done < <(find "$SRC" -type f -print0)

# The shepherd CLI wrapper.
mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/shepherd" <<'EOF'
#!/usr/bin/env bash
exec bash "$HOME/.config/opencode/plugins/shepherd/scripts/shepherd.sh" "$@"
EOF
chmod +x "$HOME/.local/bin/shepherd"

if [ -d "$BACKUP" ]; then
  echo "Backup: $BACKUP"
fi
echo "Done. Start a new OpenCode session, or run /reload."
