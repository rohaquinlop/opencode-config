# opencode-config

Personal OpenCode V2 configuration: global instructions, agents, skills, commands, and plugins.

Inspired by several agent-driven development workflows.

## Install

```sh
git clone https://github.com/rohaquinlop/opencode-config.git
cd opencode-config
./install.sh
```

The script copies every file in `config/` into `~/.config/opencode/`. Existing files are moved to
`~/.opencode-config-backup-<timestamp>/` first. Nothing is deleted. It is safe to re-run.

## Capture changes

Edit the live config in `~/.config/opencode/`, then run:

```sh
cd ~/opencode-config
./sync.sh
```

The script copies the live config back into `config/`, strips runtime files, replaces home paths
with `~`, runs a secret scan, and shows `git status`. Review it, commit, and push.

```sh
git add -A
git commit -m "chore: update opencode config"
git push
```

## Layout

```text
config/
├── AGENTS.md            global instructions
├── opencode.json        default model and update policy
├── cli.json             TUI theme and input settings
├── agents/              codebase-scout, senior-code-reviewer, web-research-synthesizer, shepherd-reviewer*
├── commands/            /be-terse/mode, /shepherd/*, /cache-*, /jira, /slack, /handoff
├── skills/              git-commit, create-pr, handoff, jira, slack, ship, bro, system-map, shepherd-*
└── plugins/
    ├── be-terse/        terseness instruction on every root-session prompt
    ├── shepherd/        pre-push gate, diagnosis guard, session resume, stop nudge, CLI
    ├── deepseek-cache/  date/env freeze, telemetry, prefix guard, deterministic compaction
    └── workflow-hooks/  destructive-git block, Python edit checks, Python stop gate
```

## Models

- Default: `deepseek/deepseek-flash`.
- `shepherd-reviewer`: `deepseek/deepseek-flash#low` for routine reviews and verify calls.
- `shepherd-reviewer-strong`: `deepseek/deepseek-v4-pro#high` for round 1 pre-PR calls 2+ and plan review calls 2+.
- `senior-code-reviewer`: `deepseek/deepseek-v4-pro`.

## Herdr

The herdr server config is stowed from `~/.dotfiles/herdr`. Install the OpenCode integration with:

```sh
herdr integration install opencode
herdr integration status
```

Herdr-generated files are machine-local and not tracked here.

## Not included

- `service.json`, logs, session history, credentials, and API keys.
- Machine-specific paths. The config uses `~` and `$HOME`.

## Before you push

Run the scan:

```sh
grep -rniE "ghp_|github_pat_|sk-[A-Za-z0-9]{10,}|AKIA[0-9A-Z]{16}|-----BEGIN|xox[baprs]-|/home/|/Users/" config/
```

Then commit with a conventional message.
