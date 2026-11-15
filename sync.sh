#!/usr/bin/env bash
# Capture the live ~/.config/opencode back into this repository, then show the
# diff. Review it, commit, and push.
#
# Runtime files (service.json, cli.json, logs, .env files) are never copied.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SYNC_SRC:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
DEST="${SYNC_DEST:-$REPO_DIR/config}"

mkdir -p "$DEST"

# Fail before touching the tree: the copy loop below rewrites config/ in place.
python3 - "$SRC/opencode.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if path.is_file():
    try:
        json.loads(path.read_text())
    except ValueError as exc:
        raise SystemExit(f"sync: {path} is not valid JSON ({exc}). Fix it and re-run.")
PY

for item in AGENTS.md opencode.json README.md agents commands skills plugins; do
  [ -e "$SRC/$item" ] || continue
  rm -rf "$DEST/$item"
  cp -a "$SRC/$item" "$DEST/$item"
done

rm -f "$DEST/service.json" "$DEST/cli.json"
rm -f "$DEST/plugins/herdr-agent-state.js" "$DEST/herdr-tui-session.js" "$DEST/tui.jsonc"
rm -rf "$DEST/herdr-opencode"
find "$DEST" -name '*.log' -delete
find "$DEST" \( -name '.env' -o -name '.env.*' \) ! -name '.env.example' -delete

# The model is a per-machine choice: shipping it pins every session.
python3 - "$DEST/opencode.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if path.is_file():
    data = json.loads(path.read_text())
    if data.pop("model", None) is not None:
        path.write_text(json.dumps(data, indent=2) + "\n")
        print(f"dropped model pin from {path.relative_to(path.parent.parent)}")
PY

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
