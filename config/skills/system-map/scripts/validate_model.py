#!/usr/bin/env python3
"""Validate a system-map model.json before it is rendered.

Every claim in a board must resolve to something real on disk. This script is the
gate: it exits non-zero with a list of problems, and the skill must not render
until it passes.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Optional

NODE_CAP = 25
PAYLOAD_SOFT_CAP = 6
SHAPES = {"flat", "slab", "cube", "stack", "tower"}
# Must track assets/board.html: height in px, and the isometric tile half-height.
HEIGHTS = {"flat": 12, "slab": 30, "cube": 58, "stack": 54, "tower": 120}
TILE_HALF_H = 37
KINDS = {"control", "data", "retry", "feedback"}
DELTAS = {"added", "removed", "modified", "unchanged"}
ORIGINS = {"typedef", "fixture", "sample", "docstring", "logfmt"}
MODES = {"map", "change", "flow"}
TRANSPORTS = {"call", "import", "queue", "http", "stream", "fs"}
SOURCES = {"code", "doc"}
SOURCE_ORIGINS = {"file", "captured"}

CITE = re.compile(r"^(?P<path>[^:]+?)(?::(?P<a>\d+)(?:-(?P<b>\d+))?)?$")


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.note: Optional[str] = None

    def err(self, where: str, msg: str) -> None:
        self.errors.append(f"{where}: {msg}")

    def warn(self, where: str, msg: str) -> None:
        self.warnings.append(f"{where}: {msg}")


def check_citation(rep: Report, root: Path, where: str, cite: Any,
                   repos: Optional[dict] = None) -> None:
    """Check one citation.

    Single-repo form: `path`, `path:line`, `path:start-end`, relative to root.
    Multi-repo form:  `<repoId>:path[:lines]`, resolved under that repo's path.
    A citation with no known repo prefix stays workspace-relative, which is how
    seeding documents that sit above the repos are cited.
    """
    if not isinstance(cite, str) or not cite.strip():
        rep.err(where, "citation must be a non-empty string")
        return
    cite = cite.strip()
    base = root
    if repos:
        head, _, rest = cite.partition(":")
        if head in repos and rest:
            base = root / repos[head]
            cite = rest
    m = CITE.match(cite)
    if not m:
        rep.err(where, f"malformed citation {cite!r}")
        return
    rel = m.group("path")
    if rel.startswith("/"):
        rep.err(where, f"citation must be repo-relative, got {cite!r}")
        return
    target = base / rel
    if not target.exists():
        rep.err(where, f"cited path does not exist: {target}")
        return
    if target.is_dir():
        if m.group("a"):
            rep.err(where, f"line range on a directory: {cite}")
        return

    a, b = m.group("a"), m.group("b")
    if not a:
        return
    start, end = int(a), int(b) if b else int(a)
    if start < 1 or end < start:
        rep.err(where, f"nonsensical line range in {cite}")
        return
    try:
        total = sum(1 for _ in target.open("rb"))
    except OSError as exc:
        rep.warn(where, f"could not read {rel} to check line bounds ({exc})")
        return
    if end > total:
        rep.err(where, f"{cite} runs past end of file ({total} lines)")


def check_occlusion(rep: Report, label: str, nodes: list) -> None:
    """Warn when a tall building hides the one behind it.

    Buildings paint back to front by `gx + gy`, so a node further forward on a
    near-enough diagonal can swallow a shorter node behind it entirely. This is
    the single most common way a board renders a node the reader never sees.
    """
    placed = [n for n in nodes
              if isinstance(n.get("grid"), list) and len(n.get("grid")) == 2
              and n.get("shape") in HEIGHTS]
    for back in placed:
        bx, by = back["grid"]
        for front in placed:
            if front is back:
                continue
            fx, fy = front["grid"]
            dsum = (fx + fy) - (bx + by)
            if not 1 <= dsum <= 3:
                continue
            if abs((fx - fy) - (bx - by)) > 1:
                continue
            gain = HEIGHTS[front["shape"]] - HEIGHTS[back["shape"]]
            if gain > dsum * TILE_HALF_H - 25:
                rep.warn(label, f"{front.get('id')!r} ({front['shape']}) stands in "
                                f"front of {back.get('id')!r} and will hide it; move "
                                f"one of them off the diagonal")


def check_board(rep: Report, root: Path, board: dict, mode: str, label: str,
                board_ids: set[str], payload_ids: set[str],
                repos: Optional[dict] = None) -> None:
    nodes = board.get("nodes")
    if not isinstance(nodes, list) or not nodes:
        rep.err(label, "board has no nodes")
        return
    edges = board.get("edges") or []
    groups = board.get("groups") or []

    if len(nodes) > NODE_CAP:
        rep.err(label, f"{len(nodes)} nodes exceeds the cap of {NODE_CAP}; "
                       "collapse a cluster into a parent node with `children`")

    group_ids = set()
    for i, g in enumerate(groups):
        gid = g.get("id")
        if not gid:
            rep.err(f"{label}.groups[{i}]", "missing id")
        elif gid in group_ids:
            rep.err(f"{label}.groups[{i}]", f"duplicate group id {gid!r}")
        else:
            group_ids.add(gid)
        if not g.get("label"):
            rep.err(f"{label}.groups[{i}]", "missing label")

    ids: set[str] = set()
    cells: dict[tuple, str] = {}
    for i, n in enumerate(nodes):
        w = f"{label}.nodes[{i}]"
        nid = n.get("id")
        if not nid:
            rep.err(w, "missing id")
        elif nid in ids:
            rep.err(w, f"duplicate node id {nid!r}")
        else:
            ids.add(nid)
        w = f"{label}.nodes[{nid or i}]"

        for field in ("label", "purpose"):
            if not n.get(field):
                rep.err(w, f"missing {field}")
        if not n.get("built"):
            rep.warn(w, "no `built` text; the HOW IT'S BUILT tab will be empty")

        purpose = n.get("purpose") or ""
        if purpose.count(".") > 1 or re.search(r"\band\b.*\band\b", purpose):
            rep.warn(w, "purpose reads like more than one responsibility; "
                        "consider splitting the node")

        shape = n.get("shape")
        if shape not in SHAPES:
            rep.err(w, f"shape must be one of {sorted(SHAPES)}, got {shape!r}")

        grid = n.get("grid")
        if (not isinstance(grid, list) or len(grid) != 2
                or not all(isinstance(v, (int, float)) for v in grid)):
            rep.err(w, "grid must be [x, y] numbers")
        else:
            key = (grid[0], grid[1])
            if key in cells:
                rep.err(w, f"grid cell {key} already used by {cells[key]!r}")
            else:
                cells[key] = nid or str(i)

        if groups and n.get("group") not in group_ids:
            rep.err(w, f"group {n.get('group')!r} is not declared in groups")

        files = n.get("files")
        if not isinstance(files, list) or not files:
            rep.err(w, "`files` is required and must name at least one real path")
        else:
            for j, f in enumerate(files):
                check_citation(rep, root, f"{w}.files[{j}]", f, repos)

        r = n.get("repo")
        if repos and len(repos) > 1:
            if not r:
                rep.err(w, "multi-repo board: every node must name its `repo`")
            elif r not in repos:
                rep.err(w, f"repo {r!r} is not declared in `repos`")

        d = n.get("delta")
        if d is not None and d not in DELTAS:
            rep.err(w, f"delta must be one of {sorted(DELTAS)} or null, got {d!r}")
        if mode == "change" and d is None:
            rep.warn(w, "change mode but no delta; node will render dimmed")

        kids = n.get("children")
        if kids and kids not in board_ids:
            rep.err(w, f"children board {kids!r} is not defined in `boards`")

    for i, e in enumerate(edges):
        w = f"{label}.edges[{i}]"
        for end in ("from", "to"):
            if e.get(end) not in ids:
                rep.err(w, f"{end} {e.get(end)!r} is not a node on this board")
        if e.get("from") == e.get("to"):
            rep.warn(w, "self-edge; a node talking to itself is usually noise")
        if e.get("kind") not in KINDS:
            rep.err(w, f"kind must be one of {sorted(KINDS)}, got {e.get('kind')!r}")
        check_citation(rep, root, f"{w}.evidence", e.get("evidence"), repos)

        t = e.get("transport")
        if t is not None and t not in TRANSPORTS:
            rep.err(w, f"transport must be one of {sorted(TRANSPORTS)} or null, "
                       f"got {t!r}")
        elif t is None and repos and len(repos) > 1:
            rep.err(w, "a multi-repo board must say how each pair talks; set "
                       "`transport`. An arrow that hides a queue behind it reads "
                       "as a direct call and misleads.")

        src = e.get("source", "code")
        if src not in SOURCES:
            rep.err(w, f"source must be one of {sorted(SOURCES)}, got {src!r}")
        elif src == "doc":
            rep.warn(w, "asserted by a seeding document, not confirmed in code; "
                        "it will render as unconfirmed")
        p = e.get("payload")
        if p is not None and p not in payload_ids:
            rep.err(w, f"payload {p!r} is not defined")
        d = e.get("delta")
        if d is not None and d not in DELTAS:
            rep.err(w, f"delta must be one of {sorted(DELTAS)} or null, got {d!r}")

    check_occlusion(rep, label, nodes)

    touched = {e.get("from") for e in edges} | {e.get("to") for e in edges}
    for nid in sorted(ids - touched):
        rep.warn(label, f"node {nid!r} has no edges; is it really part of the system?")

    steps = board.get("steps") or []
    for i, s in enumerate(steps):
        idx = s.get("edge")
        if not isinstance(idx, int) or not (0 <= idx < len(edges)):
            rep.err(f"{label}.steps[{i}]", f"edge index {idx!r} out of range")
    if mode == "flow" and not steps:
        rep.err(label, "flow mode requires `steps` so TRACE ONE STEP has an order")


def validate(path: Path, root: Path) -> Report:
    rep = Report()
    try:
        model = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        rep.err(str(path), f"invalid JSON: {exc}")
        return rep
    if not isinstance(model, dict):
        rep.err(str(path), "top level must be an object")
        return rep

    mode = model.get("mode", "map")
    if mode not in MODES:
        rep.err("mode", f"must be one of {sorted(MODES)}, got {mode!r}")

    repo = model.get("repo") or {}
    if not repo.get("name"):
        rep.err("repo", "missing name")
    if not repo.get("ref"):
        rep.warn("repo", "no ref; the board will not say which revision it describes")

    # repos: declared once, resolved for every citation that names one.
    repos: dict[str, str] = {}
    declared = model.get("repos") or []
    if not isinstance(declared, list):
        rep.err("repos", "must be a list")
        declared = []
    for i, r in enumerate(declared):
        w = f"repos[{i}]"
        rid = r.get("id")
        if not rid:
            rep.err(w, "missing id")
            continue
        if rid in repos:
            rep.err(w, f"duplicate repo id {rid!r}")
            continue
        rel = r.get("path", rid)
        if str(rel).startswith("/"):
            rep.err(w, f"path must be relative to the workspace root, got {rel!r}")
            continue
        if not (root / rel).is_dir():
            rep.err(w, f"repo path does not exist: {root / rel}")
            continue
        repos[rid] = rel
        if not r.get("ref"):
            rep.warn(w, f"repo {rid!r} has no ref; on a multi-repo board the "
                        "branches usually differ and that matters")
    if len(repos) > 1 and ":" in str(repo.get("name", "")):
        rep.warn("repo.name", "looks like a citation; it should be the workspace name")

    # sources: the documents that seeded the board. Context given verbally or
    # pasted in chat counts, but only once it has been written to a file.
    seen_sources: set[str] = set()
    for i, sd in enumerate(model.get("sources") or []):
        w = f"sources[{i}]"
        sid = sd.get("id")
        if not sid:
            rep.err(w, "missing id")
        elif sid in seen_sources:
            rep.err(w, f"duplicate source id {sid!r}")
        else:
            seen_sources.add(sid)
        origin = sd.get("origin", "file")
        if origin not in SOURCE_ORIGINS:
            rep.err(w, f"origin must be one of {sorted(SOURCE_ORIGINS)}, "
                       f"got {origin!r}")
        check_citation(rep, root, f"{w}.path", sd.get("path"), repos)

    boards = model.get("boards") or {}
    if not isinstance(boards, dict):
        rep.err("boards", "must be an object keyed by board id")
        boards = {}

    payloads = model.get("payloads") or []
    payload_ids: set[str] = set()
    for i, p in enumerate(payloads):
        w = f"payloads[{i}]"
        pid = p.get("id")
        if not pid:
            rep.err(w, "missing id")
        elif pid in payload_ids:
            rep.err(w, f"duplicate payload id {pid!r}")
        else:
            payload_ids.add(pid)
        if not p.get("label"):
            rep.err(w, "missing label")
        if not p.get("snippet"):
            rep.err(w, "missing snippet; payloads are quoted, never authored")
        if p.get("origin") not in ORIGINS:
            rep.err(w, f"origin must be one of {sorted(ORIGINS)}, "
                       f"got {p.get('origin')!r}")
        check_citation(rep, root, f"{w}.source", p.get("source"), repos)
    for bid, b in boards.items():
        for i, p in enumerate(b.get("payloads") or []):
            if p.get("id"):
                payload_ids.add(p["id"])
            check_citation(rep, root, f"boards.{bid}.payloads[{i}].source",
                           p.get("source"), repos)
    if len(payload_ids) > PAYLOAD_SOFT_CAP:
        rep.warn("payloads", f"{len(payload_ids)} payloads; the point is a few real "
                             "ones, not many. Cut to the ones that carry meaning.")

    board_ids = set(boards)
    check_board(rep, root, model, mode, "root", board_ids, payload_ids, repos)
    for bid, b in boards.items():
        check_board(rep, root, b, mode, f"boards.{bid}", board_ids, payload_ids,
                    repos)

    reachable = {"root"}
    def walk(board: dict) -> None:
        for n in board.get("nodes") or []:
            kid = n.get("children")
            if kid and kid in boards and kid not in reachable:
                reachable.add(kid)
                walk(boards[kid])
    walk(model)
    for bid in sorted(board_ids - reachable):
        rep.warn("boards", f"board {bid!r} is unreachable; no node points at it")

    x = model.get("explainer") or {}
    if not x.get("what"):
        rep.err("explainer.what", "required; this is the paragraph that makes the "
                                  "picture mean something")
    if not x.get("howToRead"):
        rep.warn("explainer.howToRead", "missing; readers get no legend in prose")
    if mode == "change" and not (model.get("diff") or {}).get("summary"):
        rep.err("diff.summary", "change mode requires a prose summary of the change")

    all_edges = list(model.get("edges") or [])
    for b in boards.values():
        all_edges += list(b.get("edges") or [])
    doc_only = [e for e in all_edges if e.get("source") == "doc"]
    if doc_only and not model.get("sources"):
        rep.err("sources", "the board has doc-asserted edges but declares no "
                           "`sources`; say which document made the claim")
    if all_edges:
        rep.note = (f"{len(all_edges) - len(doc_only)}/{len(all_edges)} edges "
                    f"confirmed in code"
                    + (f", {len(doc_only)} asserted by documents only"
                       if doc_only else ""))
    return rep


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("model", type=Path, help="path to model.json")
    ap.add_argument("--root", type=Path, default=None,
                    help="repo root that citations are relative to "
                         "(default: current directory)")
    ap.add_argument("--strict", action="store_true",
                    help="treat warnings as errors")
    args = ap.parse_args()

    root = (args.root or Path.cwd()).resolve()
    if not args.model.exists():
        print(f"no such model: {args.model}", file=sys.stderr)
        return 2

    rep = validate(args.model, root)
    for w in rep.warnings:
        print(f"WARN  {w}")
    for e in rep.errors:
        print(f"ERROR {e}")

    n_e, n_w = len(rep.errors), len(rep.warnings)
    if n_e:
        print(f"\n{n_e} error(s), {n_w} warning(s) — do not render until the "
              f"errors are fixed.")
        return 1
    if n_w and args.strict:
        print(f"\n{n_w} warning(s), --strict — treating as failure.")
        return 1
    print(f"\nOK — {n_w} warning(s). Citations resolve against {root}.")
    if rep.note:
        print(rep.note)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
