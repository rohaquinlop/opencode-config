#!/usr/bin/env bash
# Link this repository's config/ tree into ~/.config/opencode.
#
# Existing files are moved to ~/.opencode-config-backup-<timestamp>/ first.
# Nothing is deleted. Safe to re-run: files already linked to this repo are
# skipped.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/config"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
BACKUP="$HOME/opencode-config-backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$DEST"

link() {
  local src="$1"
  local rel="${src#"$SRC"/}"
  local dest="$DEST/$rel"

  mkdir -p "$(dirname "$dest")"

  if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
    return
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    mkdir -p "$(dirname "$BACKUP/$rel")"
    mv "$dest" "$BACKUP/$rel"
  fi

  ln -s "$src" "$dest"
  echo "linked $rel"
}

while IFS= read -r -d '' file; do
  link "$file"
done < <(find "$SRC" -type f -print0)

# The shepherd CLI wrapper. It always resolves through the linked config.
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
