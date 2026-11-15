# shepherd (OpenCode)

Drives one change from an issue to a merge-ready PR. Stops only for decisions that need you.

## Commands

```text
/shepherd/run 123
/shepherd/run TS-123
/shepherd/run <pasted story>
/shepherd/diagnose <symptom>
/shepherd/followup <side issue>
```

## Flow

study → brief → implement → targeted checks → fresh read-only review (max 3) → verify → push → CI → triage → merge-ready.

## Reviewers

| Agent | Tier | Used for |
| --- | --- | --- |
| `shepherd-reviewer` | routine | Routine reviews, round 2+, verify calls, when a PR exists |
| `shepherd-reviewer-strong` | strong | Round 1 pre-PR calls 2+, plan review calls 2+ |

Tier models come from `plugins/model-tiers/tiers.json`.

## State

```text
<repo>/.opencode/shepherd/<branch>/
```

Per-repo config: `<repo>/.opencode/shepherd.json`.

CLI: `shepherd` on PATH.

## Hooks

- Pre-push gate: blocks a push unless the reviewed tree is cleared.
- Diagnosis guard: keeps a diagnosis read-only.
- Session resume: loads branch state on the first prompt.
- Stop nudge: sends the next step while a phase is active, at most 3 times.

## Requires

`git`, `gh` (authenticated), `jq`.
