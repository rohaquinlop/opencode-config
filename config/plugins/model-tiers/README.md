# model-tiers (OpenCode)

Subagent model selection from a per-provider tier map, plus a sticky model
default.

## Tiers

`tiers.json` maps agent -> tier -> provider -> model spec
(`model-id`, optional `#variant`, trailing `*` = prefix wildcard):

- `routine` -> `codebase-scout`, `shepherd-reviewer`
- `strong` -> `shepherd-reviewer-strong`, `senior-code-reviewer`

An optional `overrides` block replaces one agent's spec for one provider
(`overrides.<agent>.<provider>`), used to keep per-agent DeepSeek choices.

Wildcard rule: prefer the exact base id, then non-snapshot ids (no trailing
`-<6+ digits>` date stamp), then the highest version by numeric-aware compare
(so `4-10` beats `4-9`).

Mapped subagents inherit the parent session's model, then a
`experimental.model.resolve` hook substitutes the tier's model **of the same
provider as the running model**. Adding a subscription later means adding one
column to `tiers.json`, not editing agent files. A `#variant` suffix applies
only when the resolved model declares that variant.

Fallback: no column for the running provider, no wildcard match, or no map
means the subagent keeps the inherited session model. A "configured default
provider" fallback is not possible: the model-resolve hook rejects
cross-provider substitution.

The Claude column (`claude-haiku-*` / `claude-opus-*`) is inert until the
Anthropic provider is connected; patterns then resolve against its catalog at
request time.

## Sticky default

The latest model used by a non-mapped agent is recorded and applied as the
catalog default, because OpenCode does not persist `/models` picks across
sessions. New sessions start on it. The trigger is broad on purpose: any
request of a non-mapped agent counts (a `/models` pick, an
`opencode run --model ...` run), matching "the latest model I set should
remain". The resolve event exposes no narrower signal.

## Log

Resolutions append JSONL to `<tmpdir>/opencode/model-tiers.log` (deduped per
agent): `resolve` entries carry `reason` (`tier`, `override`,
`tier-variant-dropped`, `catalog-empty`, `inherit-no-column`,
`inherit-no-match`); `sticky-default` entries record a new default. Inspect with:

```sh
grep '"event":"resolve"' /tmp/opencode/model-tiers.log
```
