# opencode-config

Personal OpenCode V2 configuration: global instructions, agents, skills, commands, and plugins.

Inspired by several agent-driven development workflows.

## Install

```sh
git clone https://github.com/rohaquinlop/opencode-config.git
cd opencode-config
./install.sh
```

The script links every file in `config/` into `~/.config/opencode/`, the way a dotfiles checkout
works: each live file is a symlink to this repo, so what OpenCode reads is what git tracks. It is
safe to re-run, and a run with nothing to do prints nothing.

OpenCode writes its own runtime files into the same directory: `cli.json` (theme, verbosity), `service.json`, and herdr output. They are not in `config/`, so they stay real files and are never linked or touched. The model lives in OpenCode's state, not here.

A file you delete from `config/` loses its link on the next run. Earlier versions left
`~/opencode-config-backup-*` directories in `~`; delete them once.

## Change the config

The live files point at this repo, so an edit written through a link is already a repo change.
An editor that saves by renaming replaces the link with a plain file; the next `./install.sh`
puts the repo copy back and drops that edit, so save in place or edit `config/` directly.
Review the change and commit:

```sh
git status
git add -A
git commit -m "chore: update opencode config"
git push
```

Run the secret scan below before you commit.

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
- The model is per-machine: `opencode.json` does not set it. New sessions follow the model last picked with `/models` (the model-tiers sticky default); pick it once after the first run if a session still shows the old one.

## Herdr

The herdr server config is stowed from `~/.dotfiles/herdr`. Install the OpenCode integration with:

```sh
herdr integration install opencode
herdr integration status
```

Herdr-generated files are machine-local and not tracked here.

## Not included

Of the OpenCode config dir, only the files in `config/` are linked and tracked, so anything OpenCode writes beside them stays out of git: `service.json`, `cli.json` (theme, verbosity), `auth.json`, the session database, and logs. `.gitignore` blocks those names, and `tests/install_test.sh` fails if one appears under `config/`.

- Session history, credentials, and API keys stay in OpenCode's data dir.
- Machine-specific paths. The config uses `~` and `$HOME`.

## Before you push

Run the scan:

```sh
grep -rniE "ghp_|github_pat_|sk-[A-Za-z0-9]{10,}|AKIA[0-9A-Z]{16}|-----BEGIN|xox[baprs]-|/home/|/Users/" config/
```

Then commit with a conventional message.

Run `bash tests/install_test.sh` after changing `install.sh`.
