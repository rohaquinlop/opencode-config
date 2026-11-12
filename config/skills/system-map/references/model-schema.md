# `model.json` contract

One schema for all three modes. Mode-specific fields are additive, never
alternative. A board that validates in `map` mode still validates after `change`
annotations are added.

## Citations

Single repo — relative to `--root`:

```
src/run_loop.py            src/run_loop.py:88            src/run_loop.py:40-120
```

Multiple repos — prefix with a declared repo id:

```
checkout_api:src/publish.py:20
```

A citation whose prefix matches no declared repo id stays relative to the
workspace root. That is how seeding documents sitting above the repos are cited,
e.g. `CLAUDE.md:28`.

`scripts/validate_model.py` resolves every citation and fails the run on the
first that does not exist or whose line range runs past the end of the file.

## Top level

| Field | Required | Notes |
|---|---|---|
| `mode` | yes | `"map"` \| `"change"` \| `"flow"` |
| `repo` | yes | `{ name, ref, subtitle }`. On a multi-repo board this describes the **workspace**, e.g. `name: "platform"`, `ref: "order pipeline · 12 repos, mixed refs"`. |
| `repos` | multi-repo | Declared once, resolves every prefixed citation. |
| `sources` | if docs seeded it | The documents the board was seeded from. |
| `stats` | no | Header tiles: `[{ label, value }]`. Four or five reads best. Use real counts. |
| `groups` | yes | Ordered semantic sections for the left rail. |
| `nodes` | yes | The buildings. Capped at 25 per board. |
| `edges` | yes | The real paths between them. |
| `payloads` | no | Quoted data shapes. Three to five for the whole board. |
| `steps` | flow only | Ordered trace: `[{ edge: <index into edges>, note }]`. |
| `explainer` | yes | The prose that makes the picture mean something. |
| `diff` | change only | `{ base, head, summary }`. |
| `boards` | no | Nested boards for drill-down, keyed by id. Same shape as the root. |

## `repos`

```json
"repos": [
  { "id": "checkout_api", "label": "checkout-api", "path": "services/checkout-api",
    "ref": "feat/idempotent-writes · 9a1c2f" }
]
```

`path` is relative to the workspace root and must be a real directory. `ref` is
that repo's own branch or sha — on a real multi-repo workspace the refs differ
per service, and that difference is usually load-bearing, so record it.

Declaring more than one repo turns on three extra requirements: every node must
name its `repo`, every edge must declare a `transport`, and citations may use the
`repoId:path` prefix.

## `sources`

```json
"sources": [
  { "id": "arch-note", "path": "docs/architecture.md",
    "label": "docs/architecture.md", "origin": "file" },
  { "id": "handover", "path": ".maps/map-platform/context.md",
    "label": "context given by the author", "origin": "captured" }
]
```

The documents the board was seeded from — an architecture note, a design doc, an
ADR, a README, a root `CLAUDE.md`, a wiki page. They are listed in the explainer
panel under **seeded from**, so a reader can see what the map was built on top of.
Required if any edge has `source: "doc"`.

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Referenced from nowhere else; it just has to be unique. |
| `path` | yes | Must resolve, like any other citation. |
| `label` | no | What the panel shows. Defaults to `path`. |
| `origin` | no | `"file"` (default) — already in the workspace. `"captured"` — context the user gave in conversation, which the skill wrote to a file so it could be cited. |

**Context given in conversation still needs a file.** When someone explains the
system in chat, or pastes notes, write it verbatim to
`.maps/<mode>-<slug>/context.md` and declare it with `origin: "captured"`. Then
cite it like anything else. Nothing on a board may rest on a claim with no
artifact behind it — including a claim made by the person who asked for the map.

## `groups`

```json
{ "id": "loop", "label": "THE EVOLUTION LOOP" }
```

Order matters — it is the order the rail renders, and it should trace how the
system actually flows. Labels are shown uppercase; write them that way.

## `nodes`

```json
{
  "id": "rl",
  "code": "RL",
  "label": "Run loop",
  "group": "loop",
  "shape": "cube",
  "grid": [1, 0],
  "purpose": "Drives one generation from candidate to persisted result.",
  "built": "An async while-loop in cli_solve.py that awaits each stage and writes a checkpoint between them.",
  "condition": null,
  "files": ["src/run_loop.py:40-120"],
  "children": null,
  "delta": null
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Short, stable, unique on its board. |
| `code` | yes | One or two characters drawn on the roof. |
| `label` | yes | Two or three words. |
| `group` | yes | Must match a declared group id. |
| `repo` | multi-repo | A declared repo id. Shown in the inspector with its ref. |
| `shape` | yes | See the shape table below — shape carries meaning. |
| `grid` | yes | `[x, y]` isometric cell. Must be unique on the board. |
| `purpose` | yes | **One** plain sentence. The validator warns on two. |
| `built` | yes in practice | The `HOW IT'S BUILT` tab. Two or three sentences. |
| `condition` | no | What is currently wrong, dead, or not switched on. |
| `files` | yes | At least one resolving citation. |
| `children` | no | A key in `boards`. Enables `→ GO INSIDE`. |
| `delta` | change mode | `added` \| `removed` \| `modified` \| `unchanged`. |

### Shapes

Shape is a claim about what kind of thing the node is. Pick deliberately.

| `shape` | Reads as | Use for |
|---|---|---|
| `flat` | A pad | Config, constants, a thin adapter |
| `slab` | A wide low block | A service, a handler, an API surface |
| `cube` | A solid block | A normal working subsystem |
| `stack` | Layered plates | A store, archive, queue, or anything holding many of something |
| `tower` | Tall and narrow | Measurement, validation, gating — the parts that refuse things |

## `edges`

```json
{ "from": "rl", "to": "va", "kind": "control", "transport": "call",
  "source": "code", "payload": "generation-context",
  "evidence": "src/run_loop.py:88", "delta": null }
```

| Field | Required | Notes |
|---|---|---|
| `from` / `to` | yes | Node ids on the same board. |
| `kind` | yes | `control` (solid) \| `data` (solid) \| `retry` (dashed) \| `feedback` (dotted). |
| `transport` | multi-repo | **How** they talk. See below. |
| `source` | no | `"code"` (default) \| `"doc"`. See below. |
| `payload` | no | A `payloads[].id`. Only set it when real data crosses here. |
| `evidence` | yes | The call, import, publish, or request that proves the edge. |
| `note` | no | One line, shown when the path is selected. Mark inferences here. |
| `delta` | change mode | Same values as a node's. |

### `transport`

| Value | Tag on the board | Means |
|---|---|---|
| `call` | — | A direct function or method call |
| `import` | — | A module dependency |
| `queue` | `Q` | A broker or table-based handoff — the producer writes, the consumer polls |
| `http` | `H` | A request over the network |
| `stream` | `S` | A continuous stream or firehose |
| `fs` | `F` | The filesystem used as a channel |

Tags only appear when a board mixes transports. Required on every edge once more
than one repo is declared: an arrow that quietly hides a queue behind it reads as
a direct call, and that is a materially wrong picture.

### `source` — how much the edge is trusted

`"code"` (the default) means a real call site, insert, import, or request was
found and `evidence` points at it.

`"doc"` means a seeding document asserts the path and the code did not confirm
it. Those edges render amber with a `?`, the inspector says so plainly, and they
are collected under **claimed by docs, unconfirmed in code** in the explainer.
Put the reason in `note` — what you looked for and did not find.

Never launder a doc claim into `source: "code"` by citing the doc as evidence.
The divergence between what a document says and what the code does is usually the
most valuable thing on the board.

## `payloads`

```json
{
  "id": "generation-context",
  "label": "GenerationContext",
  "source": "src/types.py:14-52",
  "origin": "typedef",
  "snippet": "{ \"candidate_id\": \"c-0194\", \"parent\": \"c-0121\", \"budget\": 40 }"
}
```

`origin` must be one of `typedef`, `fixture`, `sample`, `docstring`, `logfmt` —
it records where the snippet was quoted from, and it is the field that stops a
payload from being invented. `snippet` is verbatim or a faithful trim of the
source. Never author one.

## `explainer`

```json
{
  "title": "The Evolution Harness",
  "subtitle": "how a strategy program gets written, tested and filed",
  "what": "markdown paragraphs",
  "howToRead": "markdown paragraphs"
}
```

`what` and `howToRead` support `**bold**` (rendered as a highlight), `` `code` ``,
and blank-line paragraph breaks. Nothing else.

`what` is the most valuable field in the file. It is what turns a diagram into an
explanation. Write it like the reference board does: say what the repository is,
say what shape the system has and why, then say the one hard thing about it.

## `boards`

```json
"boards": {
  "validation-inside": {
    "groups": [...], "nodes": [...], "edges": [...],
    "payloads": [...], "explainer": {...}
  }
}
```

Each nested board is validated with the same rules, including the node cap. A
node's `children` must name a key here, or the validator fails. Unreachable
boards produce a warning.
