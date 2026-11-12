#!/usr/bin/env python3
"""Substitute a model.json into the hand-written board template.

This is deliberately a substitution and not code generation. The template in
assets/board.html is authored once; every board that ships looks and behaves the
same, and a regenerated map produces a diffable change instead of a rewrite.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

PLACEHOLDER = "/*__MODEL__*/"
DEFAULT_TEMPLATE = Path(__file__).resolve().parent.parent / "assets" / "board.html"


def inline_model(template: str, model: dict) -> str:
    if PLACEHOLDER not in template:
        raise SystemExit(f"template is missing the {PLACEHOLDER} placeholder")
    # ASCII-only output: the page cannot be mis-decoded when a host serves it
    # without a charset, and JSON.parse turns the escapes back into real text.
    blob = json.dumps(model, ensure_ascii=True, separators=(",", ":"))
    # The model lives inside a <script> element, so a literal "<" in a quoted
    # snippet could close it early. \u003c survives JSON.parse as "<".
    blob = blob.replace("<", "\\u003c")
    return template.replace(PLACEHOLDER, blob)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("model", type=Path, help="path to model.json")
    ap.add_argument("-o", "--out", type=Path, required=True,
                    help="output html path")
    ap.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    args = ap.parse_args()

    if not args.model.exists():
        print(f"no such model: {args.model}", file=sys.stderr)
        return 2
    if not args.template.exists():
        print(f"no such template: {args.template}", file=sys.stderr)
        return 2

    try:
        model = json.loads(args.model.read_text())
    except json.JSONDecodeError as exc:
        print(f"invalid JSON in {args.model}: {exc}", file=sys.stderr)
        return 1

    html = inline_model(args.template.read_text(), model)
    nonascii = [c for c in html if ord(c) > 127]
    if nonascii:
        print(f"warning: {len(nonascii)} non-ASCII character(s) survived; the page "
              f"may be mis-decoded if served without a charset", file=sys.stderr)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(html, encoding="utf-8")

    nodes = len(model.get("nodes") or [])
    edges = len(model.get("edges") or [])
    extra = len(model.get("boards") or {})
    print(f"wrote {args.out} — {nodes} nodes, {edges} edges"
          + (f", {extra} nested board(s)" if extra else "")
          + f", {args.out.stat().st_size // 1024} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
