# Visual spec

You do not need to write any of this. `assets/board.html` already implements it.
This document exists so you know what the model will look like once rendered, and
so the template can be maintained without re-deriving intent.

## Layout

```
┌──────────────────────────────────────────────────────────────────────┐
│ REPOSITORY │ STAT │ STAT │ STAT │        PAUSE · TRACE STEP · RESET  │
├────────────┬─────────────────────────────────────┬───────────────────┤
│ THE SYSTEM │  runtime topology                   │ WHAT IT DOES │ …  │
│ [filter]   │  <breadcrumb>                       ├───────────────────┤
│            │                                     │ SELECTED MODULE   │
│ GROUP A    │        ▛▀▜   ▛▀▜                    │ Run loop          │
│  CM  …   1 │       ▟▄▄▙──▶▟▄▄▙                   │ RL · cube         │
│  RL  …   3 │            │                        │                   │
│ GROUP B    │        ▛▀▜ ◆│  ← payload            │ Drives one gen…   │
│  KN  …   3 │       ▟▄▄▙◀─┘                       │                   │
│            │                                     │ INCOMING          │
│            │  ── flow  ---- retry  ◆ payload     │ SOURCE            │
│            │  → go inside · ← come back out      │ src/run_loop.py   │
└────────────┴─────────────────────────────────────┴───────────────────┘
```

## Projection

Isometric, tile 128 × 74 px. `iso(gx, gy) = ((gx-gy)·64, (gx+gy)·37)`.
Buildings paint back to front, sorted by `gx + gy`, so nearer structures occlude
farther ones. Edges are drawn on the ground plane and are correctly hidden behind
buildings that stand in front of them.

Heights and footprints per shape:

| shape | half-extent | height | plates |
|---|---|---|---|
| `flat` | 0.40 | 12 | 1 |
| `slab` | 0.38 | 30 | 1 |
| `cube` | 0.32 | 58 | 1 |
| `stack` | 0.40 | 54 | 5 |
| `tower` | 0.20 | 120 | 1 |

Footprints stay well inside their cell on purpose. Edges run on the ground, so a
building that filled its cell would cover the paths into it.

## Edges

Routed orthogonally in grid space: `from → elbow → to`, where the elbow shares
the source's `y` and the target's `x`. Nodes on the same row or column get a
straight line. Both ends are pulled clear of the buildings they connect, so the
arrowhead lands on visible ground and direction stays readable.

- `control`, `data` — solid
- `retry` — dashed
- `feedback` — dotted

## Payloads

One diamond per edge that declares a payload, drifting from source to target on a
5.2 s cycle, staggered so they do not move in lockstep. They are painted above the
buildings so they stay clickable. Clicking one opens the snippet and its source
citation in the inspector.

`PAUSE FLOW` freezes them. In `flow` mode only edges named in `steps` carry dots.

## Interaction

| Action | Result |
|---|---|
| Hover a building or path | Tooltip with the plain description |
| Click a building | Pin it in the inspector; unrelated nodes and edges dim |
| Click a path or a payload dot | Show the path, its evidence, and the snippet |
| Double-click, or `→` | Go inside, when the node has `children` |
| `←`, or the panel button | Come back out |
| `↑` `↓` | Move selection through the rail order |
| `Escape` | Clear selection, back to the explainer |
| Drag | Pan · Scroll or `+` `−` | Zoom |
| `TRACE ONE STEP` | Advance one edge along `steps`, or along `edges` if absent |
| Rail filter | Match on label, code, or cited filename |

With nothing selected, the inspector shows the explainer. `WHAT IT DOES` gives
`explainer.what` (plus the diff summary in change mode); `HOW IT'S BUILT` gives
`explainer.howToRead` followed by every node `condition` on the board — so the
list of what is broken is always one click away.

## Modes

- **`map`** — everything at full contrast.
- **`change`** — nodes and edges with no delta render at 45% opacity, so blast
  radius is the only thing that pops. Delta colors: green added, amber modified,
  red removed. The legend gains a delta key.
- **`flow`** — `steps` drives `TRACE ONE STEP` in order, and only traced edges
  carry payload dots. Off-path nodes stay visible as context.

## Constraints the template already satisfies

- No external requests of any kind, so it works from `file://` and survives the
  Artifact CSP.
- Theme tokens on bare `:root`, dark overridden under
  `@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) }` and
  again under `:root[data-theme="dark"]`. Light is the parchment palette from the
  reference board; dark is the slate one.
- The board is absolutely positioned inside its own container. The page body never
  scrolls horizontally.
- Under 900 px the three columns stack.
- A malformed model shows a parse error in the panel instead of a blank page.
