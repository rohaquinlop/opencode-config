# Evidence rules

These rules exist because of a specific failure. The prompt that inspired this
skill was run on a real repo and produced a 130-node import graph. The verdict
was "looks cool but kinda useless." The author's correction was:

> you want individual data packets that are snippets of real data transfer, you
> don't need many different ones, you want to be able to click on them, you also
> want to be able to zoom in on individual processes to get more detail

Every rule below is downstream of that. Read them before drafting anything.

## 1. A node is a responsibility, not a file or a folder

Never derive nodes from `ls`, from the package layout, or from the import graph.
Those produce a picture of the filesystem, which the reader already has.

The test: write the `purpose` first, in one sentence, with no "and". If you
cannot, you have either two nodes or a group. A node may span six files; a single
file may host three nodes. Both are normal.

Bad: `utils`, `app`, `src/models`, `helpers`.
Good: `Run loop`, `Review gates`, `Persistence`, `Progress measurement`.

## 2. Cap the board at 25 nodes

Over the cap, find the cluster with the weakest external coupling, replace it
with one parent node, and put the detail in a nested board under `boards`. Set
`children` on the parent so `→ GO INSIDE` works.

A board of 12 that a reader understands beats a board of 40 they scroll past.
If in doubt, go smaller and let drill-down carry the depth.

## 3. No citation, no element

Every node needs a non-empty `files`. Every edge needs `evidence`. Grep and
confirm the line before you write it — do not cite from memory of the file you
read twenty tool calls ago.

The validator checks that the path exists and that the line range is inside the
file. It cannot check that the line says what you claim. That part is on you,
and it is the part that determines whether the board is worth trusting.

## 4. Payloads are quoted, never authored

Allowed sources only:

- type, dataclass, pydantic model, struct, or interface definitions → `typedef`
- test fixtures → `fixture`
- sample or golden JSON committed in the repo → `sample`
- worked examples inside docstrings → `docstring`
- log or event format strings → `logfmt`

If none exists for a path, set `payload: null` and move on. An invented payload
is worse than an absent one, because it looks exactly as real as a true one.

## 5. Few payloads, not many

Target three to five for the whole board. The validator warns above six. The
moving dots are there so you can click one and read what actually crosses that
boundary — not to make the picture busy.

Pick the payloads that carry the system's meaning: the thing the main loop passes
around, the thing that gets persisted, the thing that goes out.

## 6. Groups are semantic and ordered

Group by role in the system's flow, not by language, directory, or layer. A good
ordering usually looks like:

```
ENTRY AND CONTROL  →  THE <name> LOOP  →  SUPPORTING THE LOOP  →  WHAT COMES OUT
```

Name the loop after what the system actually does — `THE EVOLUTION LOOP`,
`THE INGEST LOOP`. If the system has no loop, say what it has instead. Never
emit `CORE`, `MISC`, or `OTHER`.

## 7. State what is wrong

`condition` is for known breakage, dead code, half-finished migrations, and
subsystems that exist but are not switched on. The single most useful sentence on
the reference board is:

> the Rust rewrite sits beside it, finished and not yet switched on

That is the kind of thing a reader cannot get from the code in an afternoon, and
it is exactly what makes the board worth opening. Look for it deliberately:
feature flags defaulting off, `TODO` clusters, duplicate implementations, tests
marked skip, config keys nothing reads.

## 8. Label uncertainty, never smooth it

When an edge is inferred rather than proven — dynamic dispatch, a queue name
matched by string, a framework calling something by convention — put `(inferred)`
at the start of the edge `note` and cite the closest real line. Do not present a
guess with the same confidence as a call site.

If you could not determine something at all, say so in the final report rather
than filling the gap.

## 9. Documents seed the map; they do not confirm it

You will often be handed something that already states the topology — an
architecture note, a design page, an ADR, a README, a root `CLAUDE.md`, a wiki
export, or just the person explaining it to you in the conversation. Use it. It
is the fastest route to a candidate node and edge list, and on a large workspace
it may be the only thing that describes the cross-service flow at all.

Context given in conversation counts as a source, but it does not get a free
pass. Write it verbatim to `context.md` in the output directory and cite that,
with `origin: "captured"`. The rule is not "cite a file" for its own sake — it is
that six months later a reader must be able to see what a claim rested on. A
sentence someone said in a chat window does not survive; a file does.

But a document is a **claim about** the system, not the system. So:

- Take the doc's topology as the hypothesis.
- Try to confirm each edge in code. Grep for the call, the insert, the publish.
- Confirmed → `source: "code"` with the real line.
- Not confirmed → `source: "doc"`, cite the document line, and put what you
  looked for in `note`.

Never cite a document as if it were code. The gap between what the doc says and
what the code does is usually the single most valuable output of the run — it is
the thing nobody could have told you without doing the work.

Docs are also where `condition` material lives (rule 7). Deprecations, terminal
services, and open decisions are usually written down long before they are
visible in code.

## 10. On a multi-repo board, say how things talk

A workspace of independently versioned services needs two extra facts per edge
that a single repo does not:

- **`transport`.** `A → B` over a database queue behaves nothing like `A → B`
  over a function call — different failure modes, different latency, different
  ownership. An untagged arrow gets read as a call, so a queue-based system drawn
  without transport is actively misleading.
- **The producing and consuming side are in different repos.** The evidence for
  one edge lives in two places: the producer's insert or publish, and the
  consumer's poll or handler. Cite the producing side, since that is what proves
  the edge exists at all.

Record each repo's own `ref`. Service branches drift apart, and a board that
mixes `main` with three feature branches should say so on its face.

Watch for the sink-versus-queue confusion: a service reading its input from a
queue may write its *results* somewhere else entirely. That output write is a real
edge, but it is not a pipeline step, and conflating the two misreads the system.

## Working order

0. **Read the seeding documents first**, if you were given any. Extract the
   claimed topology, the vocabulary the team uses, and every hint of a
   `condition`. This is a hypothesis list, nothing more (rule 9).
1. **Recon.** README, entry points, `pyproject.toml` / `package.json` / `Makefile`,
   CI config, top-level packages. Read code, not the file tree. On a multi-repo
   workspace, also record each repo's branch and sha.
2. **Find the spine.** What is the one loop, request path, or pipeline this repo
   exists to run? That becomes the middle group and the middle of the board.
3. **Draft groups, then nodes.** Apply rules 1, 2, 6. Cap-check before going on.
4. **Trace edges.** For each pair you believe talks, grep for the call, import,
   publish, or request. Delete every edge you cannot cite. Expect to delete some.
5. **Harvest payloads.** Rules 4 and 5.
6. **Hunt conditions.** Rule 7. Budget real effort here.
7. **Write the explainer.** If you cannot explain the system in four paragraphs,
   the board is probably wrong, not the prose.
8. **Lay out the grid.** Flow left to right along the spine, supporting nodes
   below, outputs to the right. Keep cells unique. Leave gaps; a crowded grid
   reads worse than a sparse one.

## Layout heuristics

- Put the spine on one row, in execution order, ascending `x`.
- Supporting subsystems go on a row below the spine.
- Outputs go furthest right, so the eye ends where the system ends.
- A `tower` next to what it measures is more legible than a tower off on its own.
- `stack` nodes read as stores; put them where data comes to rest.
- **Space the board out — step by 2, not 1.** Adjacent cells crowd the buildings
  together and bury the paths between them. `[0,0] [2,0] [4,0]` reads far better
  than `[0,0] [1,0] [2,0]`.
- **Never put a `tower` on the diagonal in front of a shorter node.** Buildings
  paint back to front, so a tall structure one or two cells forward will swallow
  whatever is behind it. The validator warns on this; take the warning seriously,
  because the alternative is a board with a node the reader never sees.
- Two nodes with a heavy relationship belong on the same row or column. Edge
  routing is orthogonal in grid space, so aligned nodes get clean straight lines.
