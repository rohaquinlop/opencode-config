#!/usr/bin/env bash
# Capture the live ~/.config/opencode back into this repository, then show the
# diff. Review it, commit, and push.
#
# Runtime files (service.json, logs, .env files) are never copied.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
DEST="$REPO_DIR/config"

mkdir -p "$DEST"

for item in AGENTS.md opencode.json cli.json README.md agents commands skills plugins; do
  [ -e "$SRC/$item" ] || continue
  rm -rf "$DEST/$item"
  cp -a "$SRC/$item" "$DEST/$item"
done

rm -f "$DEST/service.json"
find "$DEST" -name '*.log' -delete
find "$DEST" \( -name '.env' -o -name '.env.*' \) ! -name '.env.example' -delete

# Replace machine-specific home paths with ~.
python3 - "$DEST" <<'PY'
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
home = os.path.expanduser("~")
repls = [
    (f"{home}/.local/bin/shepherd", "~/.local/bin/shepherd"),
    (f"{home}/.config/opencode", "~/.config/opencode"),
    (home, "~"),
]
for path in root.rglob("*"):
    if not path.is_file():
        continue
    if path.suffix in {".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico"}:
        continue
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        continue
    next_text = text
    for old, new in repls:
        next_text = next_text.replace(old, new)
    if next_text != text:
        path.write_text(next_text)
        print(f"sanitized {path.relative_to(root)}")
PY

echo "--- git status"
git -C "$REPO_DIR" status --short
echo "--- secret scan"
if grep -rniE "ghp_|github_pat_|sk-[A-Za-z0-9]{10,}|AKIA[0-9A-Z]{16}|-----BEGIN|xox[baprs]-|/home/|/Users/" "$DEST"; then
  echo "Review the matches above before committing." >&2
else
  echo "clean"
fi
