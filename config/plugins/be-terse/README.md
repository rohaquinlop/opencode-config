# Be Terse (OpenCode port)

Installed for OpenCode at `~/.config/opencode/plugins/be-terse`. The prompt hook is
`index.ts`; `/be-terse/mode` is `~/.config/opencode/commands/be-terse/mode.md`. The
original Claude Code install instructions below are kept for reference and do not apply
to this port.


I can't stand how wordy claude is.  I've tried to get it to shut up using
CLAUDE.md, skills, etc.  But nothing worked and I started appending "respond tersely" to every prompt.

This plugin automates that. It is a `UserPromptSubmit` hook, so the style
instruction is appended to every single prompt.

This is a fork of [bigskysoftware/be-terse](https://github.com/bigskysoftware/be-terse),
installed straight from this GitHub repo so you control exactly what lands on
your machine and when.

## Modes

There are two styles. The default is Simplified Technical English.

| Mode | Instruction appended |
|------|----------------------|
| `ste` (default) | respond tersely in [Simplified Technical English](https://en.wikipedia.org/wiki/Simplified_Technical_English) |
| `caveman` | ultra-compressed caveman register: no articles, no filler, no hedging, fragments fine — code, numbers, units and error strings stay exact |

Caveman mode is inspired by [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman).
That project is a skill; this stays a hook, so the same register is applied
without the model having to decide to load anything.

### Switching modes

Use the command. It validates the value, so a typo cannot leave you in a
surprise mode:

```
/be-terse:mode              # show the active mode
/be-terse:mode caveman      # switch to caveman, saved
/be-terse:mode ste          # switch back, saved
```

The saved mode lives in `${XDG_STATE_HOME:-~/.local/state}/be-terse/mode`, so
it survives restarts. `/be-terse:mode cavemen` prints the valid modes and
changes nothing.

For a one-off, end a single prompt with a mode keyword. The hook does not
remove the keyword, so Claude still sees it as part of your prompt:

```
refactor this parser caveman   # caveman, this prompt only
refactor this parser ste       # Simplified Technical English, this prompt only
refactor this parser noterse   # append nothing at all, this prompt only
```

You can also set a session default without touching the saved mode:

```
BE_TERSE_MODE=caveman claude
```

Resolution order, first match wins:

1. trailing `noterse`
2. trailing `ste` / `caveman`
3. `$BE_TERSE_MODE`
4. the saved mode
5. `ste`

## Requirements

The hook is a bash script.

On Windows, use WSL or Git Bash.

## Install

### Option A — as a Claude Code plugin (recommended)

From inside Claude Code:

```
/plugin marketplace add rohaquinlop/be-terse
/plugin install be-terse@be-terse
```

This clones the repo — a plain git operation, no npm and no install scripts.
Restart Claude Code, then check it:

```
claude plugin list
```

To update later: `/plugin marketplace update`. Nothing updates until you run
that.

### Option B — from a local checkout

Point the marketplace at a directory you own, so nothing is fetched from the
network after the initial clone:

```
git clone https://github.com/rohaquinlop/be-terse.git
```

Then, from inside Claude Code:

```
/plugin marketplace add /path/to/be-terse
/plugin install be-terse@be-terse
```

### Option C — the hook alone, no plugin system

Point at a full checkout — the hook reads `lib/mode.sh` alongside it, so the
script is not standalone — and register the hook yourself in
`~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "bash /path/to/be-terse/hooks/append-terse.sh" }
        ]
      }
    ]
  }
}
```

`/be-terse:mode` is not available this way, since commands are registered by
the plugin. Switch with `BE_TERSE_MODE`, the per-prompt keywords, or by calling
`scripts/set-mode.sh` directly.

### Uninstall

```
claude plugin uninstall be-terse
claude plugin marketplace remove be-terse
```

## Versioning

The `version` field in [`.claude-plugin/plugin.json`](./.claude-plugin/plugin.json)
is set explicitly. Installers only receive an update when that field is bumped —
pushing a commit without bumping it does not push a new version to existing
installs.

## License

Upstream [bigskysoftware/be-terse](https://github.com/bigskysoftware/be-terse)
ships no license file, so this fork does not claim one either. Original plugin
by Carson Gross.
