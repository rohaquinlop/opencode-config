# opencode-config

Personal OpenCode V2 configuration: global instructions, agents, skills, commands, and plugins.

Inspired by several agent-driven development workflows.

## Install

```sh
git clone https://github.com/rohaquinlop/opencode-config.git
cd opencode-config
./install.sh
```

The script copies the files in `config/` into `~/.config/opencode/`. It installs missing files only.
A file that differs from the repo is reported and left alone, because OpenCode writes some of them at
runtime. It is safe to re-run.

Use `--force` to replace differing files. A forced run moves them to
`${XDG_STATE_HOME:-~/.local/state}/opencode/config-backups/<timestamp>/` first and keeps the last
five. `--dry-run` prints what would change and writes nothing.

After upgrading from the old installer, run `./install.sh --force` once: the live `opencode.json`
then loses the model pin. Delete the old `~/opencode-config-backup-*` directories by hand; the new
installer keeps its own backups and does not prune those.

## Capture changes

Edit the live config in `~/.config/opencode/`, then run:

```sh
cd ~/opencode-config
./sync.sh
```

The script copies the live config back into `config/`, strips runtime files (`cli.json`, logs), drops
a `model` key from `opencode.json`, replaces home paths with `~`, runs a secret scan, and shows
`git status`. Review it, commit, and push.

```sh
git add -A
git commit -m "chore: update opencode config"
git push
```

## Layout

```text
config/
├── AGENTS.md            global instructions
├── opencode.json        update policy and experimental flags
├── agents/              codebase-scout, senior-code-reviewer, web-research-synthesizer, shepherd-reviewer*
├── commands/            /be-terse/mode, /shepherd/*, /cache-*, /jira, /slack, /handoff
├── skills/              git-commit, create-pr, handoff, jira, slack, ship, bro, system-map, shepherd-*
└── plugins/
    ├── be-terse/        terseness instruction on every root-session prompt
    ├── shepherd/        pre-push gate, diagnosis guard, session resume, stop nudge, CLI
    ├── deepseek-cache/  date/env freeze, telemetry, prefix guard, deterministic compaction
    ├── model-tiers/     per-provider tier map for subagent models, sticky model default
    └── workflow-hooks/  destructive-git block, Python edit checks, Python stop gate
```

## Models

Subagent models come from `plugins/model-tiers/tiers.json` (tier -> model per provider) and follow the provider of the currently running model.

- Routine tier (`codebase-scout`, `shepherd-reviewer`): routine reviews and verify calls.
- Strong tier (`shepherd-reviewer-strong`, `senior-code-reviewer`): round 1 pre-PR calls 2+, plan review calls 2+, independent reviews.
- The model is per-machine: `opencode.json` does not set it, and `./sync.sh` drops a `model` key from the live file. New sessions follow the model last picked with `/models` (the model-tiers sticky default); pick it once after migrating if the first session still shows the old one.

## Herdr

The herdr server config is stowed from `~/.dotfiles/herdr`. Install the OpenCode integration with:

```sh
herdr integration install opencode
herdr integration status
```

Herdr-generated files are machine-local and not tracked here.

## Not included

- `service.json`, `cli.json` (TUI theme, verbosity), logs, session history, credentials, and API keys.
- Machine-specific paths. The config uses `~` and `$HOME`.

## Before you push

Run the scan:

```sh
grep -rniE "ghp_|github_pat_|sk-[A-Za-z0-9]{10,}|AKIA[0-9A-Z]{16}|-----BEGIN|xox[baprs]-|/home/|/Users/" config/
```

Then commit with a conventional message.

Run `bash tests/install_test.sh` after changing `install.sh` or `sync.sh`.
