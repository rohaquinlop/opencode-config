# OpenCode setup

Personal OpenCode V2 configuration. Inspired by several agent-driven development workflows.

## Layout

| Path | What |
| --- | --- |
| `opencode.json` | updates disabled, experimental flags |
| `AGENTS.md` | global instructions |
| `plugins/be-terse/` | appends a style instruction to every root-session prompt |
| `plugins/shepherd/` | pre-push gate, diagnosis guard, session resume, stop nudge, CLI |
| `plugins/deepseek-cache/` | date/env freeze, telemetry, prefix guard, deterministic compaction |
| `plugins/model-tiers/` | per-provider tier map for subagent models, sticky model default |
| `plugins/workflow-hooks/` | destructive-git block, Python edit checks, Python stop gate |
| `agents/` | `codebase-scout`, `senior-code-reviewer`, `web-research-synthesizer`, `shepherd-reviewer*` |
| `skills/` | git-commit, create-pr, handoff, jira, slack, ship, bro, poc-codebase-review, system-map, shepherd-* |
| `commands/` | `/be-terse/mode`, `/shepherd/{run,diagnose,followup}`, `/cache-{stats,graph,reset}`, `/jira`, `/slack`, `/handoff` |

The shepherd CLI is on PATH as `shepherd` (`~/.local/bin/shepherd`). It writes state to
`<repo>/.opencode/shepherd/` and reads `<repo>/.opencode/shepherd.json`.

## Models

Subagent models come from `plugins/model-tiers/tiers.json` (tier -> model per provider) and follow the provider of the currently running model.

- Routine tier (`codebase-scout`, `shepherd-reviewer`): routine reviews and verify calls.
- Strong tier (`shepherd-reviewer-strong`, `senior-code-reviewer`): round 1 pre-PR calls 2+, plan review calls 2+, independent reviews.
- The model is per-machine: `opencode.json` does not set it. New sessions are meant to follow the model last picked with `/models` (the model-tiers sticky default); if one still shows the old model after the first run, pick it once.

## Hooks

| Source hook | OpenCode |
| --- | --- |
| Prompt submission | `session.hook("prompt")` |
| Session start | `session.hook("prompt")`, first root prompt only |
| Pre-tool guard | `permission.hook("evaluate")` |
| Post-tool checks | `tool.hook("execute.after")` + `session.hook("context")` |
| Stop gate | `event.subscribe("session.idle")` + `session.prompt` |

## Herdr

The herdr server config is stowed from `~/.dotfiles/herdr`:
`~/.config/herdr/config.toml`.

Install the OpenCode integration:

```sh
herdr integration install opencode
herdr integration status
```

It generates machine-local files. They are not tracked in this repo:
`plugins/herdr-agent-state.js`, `herdr-tui-session.js`, `tui.jsonc`, `herdr-opencode/`.

## Not included

- `service.json`, `cli.json` (TUI theme, verbosity), logs, session history, credentials, and API keys.
- Machine-specific paths. The config uses `~` and `$HOME`.
- TUI status line: use `/cache-stats` or `/cache-graph`.
- OpenRouter upstream pinning: use the `deepseek` provider directly.

## Updating

The live config is linked to this tree. Edit `~/.config/opencode/` and the
change lands here: review `git status`, then commit and push.
