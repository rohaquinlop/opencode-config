# Diagnosis: shepherd-hardcoded-deepseek-models

Status: confirmed

## Symptom

Shepherd's subagents use only DeepSeek models. The user's Xiaomi MiMo subscription
(`xiaomi-token-plan-sgp`) is never used, and shepherd cannot select providers/models
from the user's settings. Impact: paid MiMo capacity goes unused; shepherd is pinned
to one vendor even when the session runs on another.

## Evidence

| What | Where | Shows |
|---|---|---|
| Default model pin | `~/.config/opencode/opencode.json` | `"model": "deepseek/deepseek-flash"` |
| Agent pins | `~/.config/opencode/agents/{codebase-scout,senior-code-reviewer,shepherd-reviewer,shepherd-reviewer-strong}.md` frontmatter | `model: deepseek/deepseek-flash`, `deepseek/deepseek-v4-pro`, `deepseek/deepseek-flash#low`, `deepseek/deepseek-flash#max` |
| Plugin does not choose models | grep of `plugins/shepherd/` (`index.ts`, `lib/`) | zero model references outside README; reviewers are spawned by name only |
| Skills do not choose models | grep of `skills/` | no `model:`/provider references in shepherd skills |
| MiMo models available | `opencode.models()` query | `xiaomi-token-plan-sgp/mimo-v2.6-flash`, `xiaomi-token-plan-sgp/mimo-v2.6-pro` (variants: none) |
| DeepSeek variants | `opencode.models()` query | `#none/#low/#high/#max` exist only on deepseek models |
| Runtime repro (below) | subagent probe | pinned agent runs deepseek even though the session runs mimo-v2.6-pro |
| MiMo deep-thinking model | https://mimo.mi.com/docs/en-US/quick-start/usage-guide/text-generation/deep-thinking | binary `thinking.type: enabled\|disabled`, default enabled on `mimo-v2.6-flash`/`pro`/`pro-ultraspeed`; no effort levels; `reasoning_content` must round-trip in multi-turn tool calls (OpenCode listed as affected client) |

## Environment checked

- Live config: `~/.config/opencode` (mirrored into this repo's `config/` by `sync.sh`).
- Repo `opencode-config`, branch `main`, clean at `e282132`.
- Providers resolved in this environment: `xiaomi-token-plan-sgp`, `deepseek`, `opencode`.
- No config block, env var, or helper maps tiers to models; nothing reads provider settings at spawn time.

## Hypotheses

| # | Hypothesis | Status | Check |
|---|---|---|---|
| H1 | Model binding is static config: 4 agent frontmatter pins + 1 `opencode.json` default; nothing resolves a model from user settings | confirmed | grep + file reads above |
| H2 | The shepherd plugin or its skills override/choose models at runtime | refuted | grep of `plugins/shepherd/` and `skills/`: no model selection code |
| H3 | Frontmatter pin wins over the session model at subagent spawn | confirmed | repro below |
| H4 | MiMo subscription is available but unreferenced | confirmed | `opencode.models()` shows both MiMo models; grep of config shows zero `xiaomi-token-plan-sgp`/`mimo-v2.6-*` references (only `commands/cache-stats.md` prose mentions "MiMo") |

## Root cause (confirmed)

Model choice for shepherd's subagents is hardcoded to `deepseek/*` in five static
config files (`opencode.json` + four `agents/*.md`). No code path reads the user's
provider settings or session model. Two extra constraints make the pins
vendor-locked as written:

- Effort suffixes (`#low`, `#max`) exist only on DeepSeek models; MiMo models have
  no variants, so a naive string swap would produce invalid pins.
- Global `AGENTS.md` prose ("deepseek-flash-tier", "deepseek-v4-pro-tier") steers
  ad-hoc subagent model choice toward DeepSeek as well.

Covers: the four named subagents and the default session model. Not checked:
whether every DeepSeek auth path still works (irrelevant to this symptom).

## Reproduction

Scratch probe: spawn `codebase-scout` (pinned `deepseek/deepseek-flash`) while the
main session runs `xiaomi-token-plan-sgp/mimo-v2.6-pro`, and ask it to report its
model. Output:

```
deepseek/deepseek-flash (DeepSeek V4.1 Flash 1017); no effort variant shown.
```

The pin wins; the session's MiMo model is ignored. A fix is regression-tested by
spawning `codebase-scout` again and asserting it reports the model configured in
the user's settings instead of a hardcoded vendor.

## Ruled out

- Shepherd plugin or skill code selecting models (H2).
- MiMo access being unavailable (models resolve in this environment).
- Variant syntax portability: `#low`/`#max` are DeepSeek-only (H4 constraint).

## Assumptions to confirm

- Confirmed by user (2026-11-15): "based on my settings" means a per-provider
  tier mapping that follows the provider of the currently running model. Today
  that is `xiaomi-token-plan-sgp` (MiMo); later it may be Anthropic (Claude).
  User's desired mapping: routine/first reviews → `mimo-v2.6-flash` (Claude:
  Haiku), strong/final review → `mimo-v2.6-pro` (Claude: Opus).

## Open checks

- None blocking. Owned by user: whether DeepSeek should remain an option in the
  mapping or be dropped entirely.
- Optional, owner fix session (needs a user yes: temporary provider `baseURL`
  override to a local capture proxy): observe `reasoning_content` on the actual
  OpenCode wire request, closing the last gap in the pass-back claim.

## Fix direction (no code)

1. Single source of truth: a tier → model map keyed **by provider**, resolved
   against the provider of the currently running model. Example shape:

   ```json
   {
     "tiers": {
       "routine": { "xiaomi-token-plan-sgp": "mimo-v2.6-flash", "anthropic": "claude-haiku-*", "deepseek": "deepseek-flash#low" },
       "strong":  { "xiaomi-token-plan-sgp": "mimo-v2.6-pro",   "anthropic": "claude-opus-*",  "deepseek": "deepseek-flash#max" }
     }
   }
   ```

   Agent roles map to tiers: `codebase-scout`, `shepherd-reviewer` → routine;
   `shepherd-reviewer-strong`, `senior-code-reviewer` → strong. Connecting a new
   subscription later means adding one column, not editing agent files.
2. Resolution mechanism: a small config-time resolver (e.g. an OpenCode plugin
   `config` hook, or a step in `install.sh`) that reads the map and the active
   model's provider and fills each agent's `model:` — instead of literal
   `deepseek/...` strings. Fallback when the active provider has no column:
   session model (inherit), then a configured default provider.
3. Effort/variant suffixes are provider capability, not part of the tier:
   MiMo deep-thinking is a binary `thinking.type` toggle (enabled by default on
   `mimo-v2.6-flash`/`pro`/`pro-ultraspeed`; no effort ladder), while DeepSeek
   exposes `#none/#low/#high/#max`. Apply `#variant` only where the resolved
   model declares variants. MiMo `reasoning_content` pass-back: validated
   post-diagnosis (below) — endpoint is lenient (no 400 on this protocol), so
   the pass-back is quality-critical, not error-critical, and OpenCode's
   round-trip is the load-bearing part.
4. Replace vendor-name prose in `AGENTS.md` and README tables with tier names.

Out of scope: the `sync.sh`/install flow, `deepseek-cache` plugin behavior.

## Acceptance criteria

- Spawning `shepherd-reviewer`, `shepherd-reviewer-strong`, `codebase-scout`,
  and `senior-code-reviewer` uses the models from the user's settings mapping;
  a probe reports the MiMo model, not `deepseek/*`.
- The mapping includes a Claude column from the start (routine → Haiku,
  strong → Opus; exact IDs resolved from the connected provider's models at fix
  time). It is inert while only MiMo is connected and activates when the Anthropic
  subscription is connected.
- Changing the mapping (e.g. back to DeepSeek) changes all four agents without
  editing each agent file.
- Variant suffixes are applied only to models that support them.

## Deadlines

None.

## Post-diagnosis validation: reasoning_content pass-back (2026-11-15)

Repro: `.opencode/shepherd/_diagnose/scratch/shepherd-hardcoded-deepseek-models/repro_reasoning_pasback.py`
(run with `uv run`; reads the credential from `opencode.db`, never prints it).
Two-turn tool call against `https://token-plan-sgp.xiaomimimo.com/v1` with
`mimo-v2.6-pro`, `@ai-sdk/openai-compatible` protocol (same as OpenCode uses
for `xiaomi-token-plan-sgp`, per models.dev):

```
turn 1: status=200 tool_calls=True reasoning_content=True
turn 2a (with reasoning_content):    status=200
turn 2b (without reasoning_content): status=200
verdict: pass-back NOT enforced by endpoint (lenient)
```

Findings:

- The MiMo-doc 400 is Anthropic-protocol behavior; the OpenAI-compatible
  token-plan SGP endpoint accepts tool-call history without `reasoning_content`.
- Risk is therefore silent quality loss (MiMo docs: incomplete context → weaker
  instruction-following, more hallucinations), not errors.
- OpenCode's round-trip is the load-bearing part: models.dev defs for
  `xiaomi-token-plan-sgp` set `reasoning: true` + `interleaved.field:
  "reasoning_content"`, and OpenCode's provider transform restores the field on
  prior assistant messages. Not yet observed on the wire (see open checks).

## Next session

`/shepherd/run /home/rohaquinlop/opencode-config/docs/diagnoses/2026-11-15-shepherd-hardcoded-deepseek-models.md`
