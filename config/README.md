# OpenCode setup

Ported from `rohaquinlop/be-terse`, `rohaquinlop/shepherd`, `rohaquinlop/pi-deepseek-cache`,
and `rohaquinlop/claude-config` on 2026-11-12.

## Layout

| Path | What |
| --- | --- |
| `opencode.json` | default model `deepseek/deepseek-flash`, updates disabled |
| `AGENTS.md` | global instructions (ported from `CLAUDE.md`) |
| `plugins/be-terse/` | appends a style instruction to every root-session prompt |
| `plugins/shepherd/` | pre-push gate, diagnosis guard, session resume, stop nudge, CLI |
| `plugins/deepseek-cache/` | date/env freeze, telemetry, prefix guard, deterministic compaction |
| `plugins/claude-hooks/` | destructive-git block, Python edit checks, Python stop gate |
| `agents/` | `codebase-scout`, `senior-code-reviewer`, `web-research-synthesizer`, `shepherd-reviewer` |
| `skills/` | git-commit, create-pr, handoff, jira, slack, ship, bro, poc-codebase-review, system-map, shepherd-* |
| `commands/` | `/be-terse/mode`, `/shepherd/{run,diagnose,followup}`, `/cache-{stats,graph,reset}`, `/jira`, `/slack`, `/handoff` |

The shepherd CLI is on PATH as `shepherd` (`~/.local/bin/shepherd`). It writes state to
`<repo>/.opencode/shepherd/` and reads `<repo>/.opencode/shepherd.json`.

## Models

- Default: `deepseek/deepseek-flash`.
- `shepherd-reviewer`: `deepseek/deepseek-flash#low` (routine pre-push and verify reviews).
- `shepherd-reviewer-strong`: `deepseek/deepseek-v4-pro#high` (round 1 pre-PR calls 2+, plan review calls 2+).
- `senior-code-reviewer`: `deepseek/deepseek-v4-pro`.

Change them in `opencode.json` or in the agent frontmatter.

## Hooks, mapped

| Claude Code | OpenCode |
| --- | --- |
| `UserPromptSubmit` (be-terse) | `session.hook("prompt")` |
| `SessionStart` (shepherd) | `session.hook("prompt")`, first root prompt only |
| `PreToolUse` (push, diagnose, git) | `permission.hook("evaluate")` |
| `PostToolUse` (Python checks) | `tool.hook("execute.after")` + `session.hook("context")` |
| `Stop` (shepherd, Python gate) | `session.hook`-free `event.subscribe("session.idle")` + `session.prompt` |

## Not ported

- `herdr` session reporting: OpenCode has its own session integration.
- Claude Code status line: no equivalent; use the `/cache-stats` tool instead.
- OpenRouter upstream pinning from pi-deepseek-cache: use the `deepseek` provider directly.
- TUI footer cache percentage: use `/cache-stats` or `/cache-graph`.

## Update from upstream

The three plugins are local copies, not git checkouts. To update, re-port the diff:

```sh
git clone https://github.com/rohaquinlop/be-terse /tmp/be-terse
git clone https://github.com/rohaquinlop/shepherd /tmp/shepherd
git clone https://github.com/rohaquinlop/pi-deepseek-cache /tmp/pi-cache
git clone https://github.com/rohaquinlop/claude-config /tmp/claude-config
```

Then compare against `plugins/*/index.ts` and `skills/`. The upstream bash scripts can often be
copied as-is; only the `.claude` paths and Claude-specific wording need changes.
