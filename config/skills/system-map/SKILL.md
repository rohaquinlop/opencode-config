---
name: system-map
description: Turn a codebase, a set of services, a change, or a runtime path into an interactive isometric system map you can point at and discuss. Works across one repo or many in a workspace, and can be seeded from architecture notes, design docs, a README or CLAUDE.md, or context given in conversation. Language- and stack-agnostic. Use when the user wants to understand how a repo is put together, how services interact, what a PR or commit range actually touched, or what happens along one entry point. Triggers on "map this repo", "system map", "map these services", "how does this fit together", "visualize the architecture", "show me what this PR changed", "trace this request", "explain this codebase visually".
---

# System Map

Produce a self-contained interactive board — isometric buildings on a grid, real
control and data paths between them, clickable payloads quoted from the code, and
an explainer panel — so the user can discuss the system by pointing at it.

The board is a means. The value is the accuracy of the model behind it. A pretty
diagram of the wrong system is worse than no diagram.

## Modes

| Mode | Argument | Answers |
|---|---|---|
| `map` (default) | optional subsystem or path scope | How is this system put together, and what talks to what? |
| `change` | PR number, branch, or commit range | What did this change touch, and what does it now talk to that it did not before? |
| `flow` | an entry point — route, CLI command, job, handler | What actually happens, in order, along this path? |

Infer the mode from the request. Ask only when genuinely ambiguous.

## Inputs it accepts

- **One repository.** The default.
- **A workspace of several repositories.** A directory whose subfolders are each
  their own git repo. Declare them in `repos`; citations get a `repoId:` prefix.
- **Seeding context.** Anything that describes the system: an architecture note,
  a design doc, an ADR, a README, a root `CLAUDE.md`, a wiki export — or the user
  simply explaining it in the conversation. Read it first for the candidate
  topology and the team's vocabulary, then confirm in code. A claim from context
  never becomes code evidence; see rule 9.
  - Context that arrives as **conversation or pasted text** has no file behind
    it. Write it verbatim to `.maps/<mode>-<slug>/context.md`, declare it in
    `sources` with `origin: "captured"`, and cite that. Never rest a board on a
    claim with no artifact.
- **A scope.** A named pipeline, subsystem, or path. When a workspace describes
  more than one pipeline over the same services, build **one board per
  pipeline** and say which one in `repo.ref`.

If the user names a document, read it before touching any code.

## Required reading

Before drafting anything, read:

- `references/evidence-rules.md` — the eight hard rules. Non-optional.
- `references/model-schema.md` — the exact shape of `model.json`.

Read `references/visual-spec.md` only if you need to know how a field renders.

## Workflow

1. **Resolve inputs.**
   - `mode`, and its argument. Any seeding documents. Any scope.
   - `root`: the workspace root that all citations resolve against.
     - Single repo: `git rev-parse --show-toplevel`.
     - Workspace: the directory holding the repos. It often is not a git repo
       itself — that is fine and expected.
   - `ref` per repo. In a workspace, loop the subfolders:
     ```
     for d in */; do git -C "$d" rev-parse --abbrev-ref HEAD; done
     ```
     Record each in `repos[].ref`. Mixed refs are normal and worth surfacing.
   - `slug`: a short kebab name for the output directory.

2. **Take in the seeding context**, if any. Pull out the claimed topology, the
   vocabulary the team actually uses, and every hint of a `condition`. Treat all
   of it as hypothesis. If any of it came from the conversation rather than a
   file, write it to `context.md` now, before you start reading code.

3. **Recon.** README, entry points, dependency manifest, CI config, top-level
   packages. Read code, not the file tree. Find the spine: the one loop, request
   path, or pipeline the system exists to run.

4. **Mode-specific gathering.**
   - `map`: nothing extra.
   - `change`: `git diff --stat <base>...<head>` and the full diff for the files
     that matter. Note which files are new, deleted, or heavily rewritten, and
     which import edges appeared or disappeared.
   - `flow`: locate the entry point, then follow the call chain by reading, not
     guessing. Record the order — it becomes `steps`.

5. **Draft groups and nodes.** Apply rules 1, 2, and 6. Cap-check at 25 before
   going further. Assign `shape` deliberately; shape is a claim.

6. **Trace edges.** For every pair you believe talks, grep for the call, import,
   publish, or request and cite the line. On a multi-repo board set `transport`
   on every edge — cite the **producing** side, since that is what proves the
   edge. An edge the code does not confirm is deleted, or kept as
   `source: "doc"` with the document line and a `note` saying what you could not
   find. Never silently keep an unproven edge.

7. **Harvest payloads.** Three to five, quoted verbatim, each with a real
   `source` and `origin`. Rules 4 and 5.

8. **Hunt conditions.** Rule 7. Feature flags off by default, `TODO` clusters,
   duplicate implementations, skipped tests, config nothing reads. Budget real
   effort here — this is often the most valuable content on the board.

9. **Write the explainer.** Four paragraphs at most in `what`: what the repo is,
   what shape the system has and why, the one hard thing about it. Then
   `howToRead`.

10. **Lay out the grid.** Spine left to right, supporting below, outputs right.
   Step cells by 2, not 1, so the paths between buildings stay visible. Never put
   a `tower` on the diagonal in front of a shorter node — it will hide it.

11. **Write the model** to `<root>/.maps/<mode>-<slug>/model.json`.

12. **Validate — hard gate.**
    ```
    python3 <skill>/scripts/validate_model.py .maps/<mode>-<slug>/model.json \
      --root <workspace root>
    ```
    Fix every error. Read every warning and either fix it or be able to justify
    it. Do not proceed to step 13 with errors outstanding.

13. **Render.**
    ```
    python3 <skill>/scripts/render.py .maps/<mode>-<slug>/model.json \
      -o .maps/<mode>-<slug>/index.html
    ```

14. **Publish.** Call the Artifact tool on the rendered `index.html`. Pass a
    `favicon` and keep it stable across regenerations of the same map. Hand back
    the URL. If Artifact is unavailable, give the local path instead.

15. **Report — short.** Three things and nothing else:
    - The one-sentence claim the board makes about the system.
    - The confirmed-vs-asserted count the validator prints, and which edges the
      documents claim that the code did not confirm. On a doc-seeded run this is
      the most valuable line in the report — lead with it.
    - The node count, and what got collapsed into a nested board.

## Rules for this skill

- **The validator is a gate, not a linter.** Never render or publish a model with
  outstanding errors, and never edit the validator to make a model pass.
- **Never author a payload.** No real source, no payload.
- **Never launder a doc claim into code evidence.** If only a document says it,
  it is `source: "doc"`, and the board says so.
- **Never invent a citation.** Grep before you write it.
- **Do not regenerate `assets/board.html`.** It is authored once, by hand. If the
  board needs a new capability, change the template deliberately and once — never
  emit a bespoke renderer per run.
- **Do not create `.gitignore` entries without asking.** Mention that `.maps/` is
  probably worth ignoring and let the user decide.
- **Re-render is cheap.** When the user corrects a node, edit `model.json` and
  re-run steps 11 to 13. Do not redo the analysis.

## Regenerating an existing map

If `.maps/<mode>-<slug>/model.json` already exists, read it first. Update it in
place so the diff shows what changed about the system, and re-publish to the same
Artifact URL by passing `url`. A map whose URL churns on every run is not a
reference.

## Layout and shape quick reference

| shape | reads as | use for |
|---|---|---|
| `flat` | a pad | config, constants, thin adapter |
| `slab` | wide low block | service, handler, API surface |
| `cube` | solid block | a normal working subsystem |
| `stack` | layered plates | store, archive, queue |
| `tower` | tall and narrow | validation, measurement, gating |

## Portability

Both scripts are Python 3 with **no third-party imports** — `argparse`, `json`,
`pathlib`, `re`, `sys` only. They run anywhere Python 3.9+ is installed, with no
install step and no virtualenv. `python3` is written above because it works on
every machine; if a project standardises on a runner, `uv run` and `poetry run`
work identically.

Nothing in this skill assumes a language, framework, VCS host, or company
convention. It reads whatever is in front of it and cites what it finds.

## Files

```
SKILL.md                        this file
references/evidence-rules.md    the eight hard rules + working order
references/model-schema.md      model.json field by field
references/visual-spec.md       what the renderer does with each field
assets/board.html               the board template — authored once, never generated
scripts/validate_model.py       the gate
scripts/render.py               model.json -> index.html
fixtures/example-model.json     a working model, for reference and for testing
```
