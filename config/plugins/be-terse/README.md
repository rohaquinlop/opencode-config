# be-terse (OpenCode)

Appends a terseness instruction to every root-session prompt.

## Modes

| Mode | Instruction |
| --- | --- |
| `ste` (default) | Respond tersely in Simplified Technical English |
| `caveman` | Ultra-compressed register. No articles, filler, hedging. Fragments fine. Code, numbers, units, and error strings stay exact. |

## Switch

```text
/be-terse/mode
/be-terse/mode caveman
/be-terse/mode ste
```

The saved mode lives in `${XDG_STATE_HOME:-~/.local/state}/be-terse/mode`.

## One prompt

End a prompt with `ste`, `caveman`, or `noterse`. The keyword is not removed, so the model still sees it.

## Environment

`BE_TERSE_MODE=caveman` sets the session default.

## Subagents

Root sessions only. Subagent prompts are not modified.
