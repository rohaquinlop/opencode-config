/**
 * Model selection policy.
 *
 * Tier map (tiers.json): mapped subagents inherit the parent session's model,
 * then this plugin swaps the request to the tier's model of the same provider
 * as the running model. Effort variants apply only where the model declares
 * them. The model-resolve hook only allows same-provider substitution, so a
 * missing column or match falls back to the inherited session model.
 *
 * Sticky default: the latest model used by a non-mapped agent becomes the
 * catalog default, so new sessions start on the model last picked with
 * /models (OpenCode does not persist those picks across sessions).
 */

import { Plugin } from "@opencode/plugin"
import { appendFileSync, mkdirSync, readFileSync, statSync } from "node:fs"
import { join } from "node:path"
import { fileURLToPath } from "node:url"
import { tmpdir } from "node:os"

type Spec = string

interface TierMap {
  agents: Record<string, string>
  tiers: Record<string, Record<string, Spec>>
  overrides?: Record<string, Record<string, Spec>>
}

interface ModelRef {
  providerID: string
  id: string
  variant?: string
}

const MAP_PATH = fileURLToPath(new URL("tiers.json", import.meta.url))
const LOG_DIR = join(tmpdir(), "opencode")
const LOG = join(LOG_DIR, "model-tiers.log")

let mapCache: { mtimeMs: number; map: TierMap | undefined } | undefined
const lastLogged = new Map<string, string>()

function loadMap(): TierMap | undefined {
  try {
    const mtimeMs = statSync(MAP_PATH).mtimeMs
    if (mapCache?.mtimeMs === mtimeMs) return mapCache.map
    const map = JSON.parse(readFileSync(MAP_PATH, "utf8")) as TierMap
    mapCache = { mtimeMs, map }
    return map
  } catch {
    mapCache = { mtimeMs: -1, map: undefined }
    return undefined
  }
}

function log(entry: Record<string, unknown>): void {
  try {
    mkdirSync(LOG_DIR, { recursive: true })
    appendFileSync(LOG, JSON.stringify({ ts: new Date().toISOString(), ...entry }) + "\n")
  } catch {
    // logging must never break resolution
  }
}

function logOnce(agent: string, entry: Record<string, unknown>): void {
  const line = JSON.stringify(entry)
  if (lastLogged.get(agent) === line) return
  lastLogged.set(agent, line)
  log({ agent, ...entry })
}

function parseSpec(spec: Spec): ModelRef {
  const at = spec.indexOf("#")
  return at < 0 ? { id: spec } : { id: spec.slice(0, at), variant: spec.slice(at + 1) }
}

function variantDeclared(model: any, variant: string | undefined): boolean {
  if (!variant) return false
  const declared: readonly any[] = Array.isArray(model?.variants) ? model.variants : []
  return declared.some((v) => (typeof v === "string" ? v : v?.id) === variant)
}

function resolveSpec(spec: Spec, providerID: string, models: readonly any[]): ModelRef | undefined {
  const { id, variant } = parseSpec(spec)
  const pool = models.filter((m) => m?.providerID === providerID)
  let match: any
  if (id.endsWith("*")) {
    const prefix = id.slice(0, -1)
    const base = prefix.replace(/[-_ ]+$/, "")
    const hits = pool.filter((m) => typeof m?.id === "string" && m.id.startsWith(prefix))
    match =
      hits.find((m) => m.id === base) ??
      hits.sort((a, b) => String(a.id).localeCompare(String(b.id))).at(-1)
  } else {
    match = pool.find((m) => m?.id === id)
  }
  if (!match) return undefined
  return variantDeclared(match, variant)
    ? { providerID, id: String(match.id), variant }
    : { providerID, id: String(match.id) }
}

export default Plugin.define({
  id: "model-tiers",
  async setup(ctx) {
    const saved: any = await ctx.storage.get("lastModel")
    let current: ModelRef | undefined =
      saved && typeof saved === "object" && typeof saved.providerID === "string" && typeof saved.id === "string"
        ? { providerID: saved.providerID, id: saved.id }
        : undefined

    async function catalog(): Promise<any[]> {
      try {
        const raw: any = await (ctx.model as any).list()
        return Array.isArray(raw) ? raw : (raw?.data ?? [])
      } catch {
        return []
      }
    }

    async function appliedDefault(): Promise<Record<string, unknown>> {
      try {
        const d: any = await (ctx.model as any).default()
        return {
          appliedProviderID: d?.data?.providerID ?? d?.providerID ?? null,
          appliedID: d?.data?.id ?? d?.id ?? null,
        }
      } catch {
        return {}
      }
    }

    await (ctx.model as any).transform((editor: any) => {
      if (!current) return
      const known = editor
        .list()
        .some((m: any) => m.providerID === current!.providerID && m.id === current!.id)
      if (known) editor.default.set(current.providerID, current.id)
    })

    if (current) {
      log({ event: "default-applied", providerID: current.providerID, id: current.id, ...(await appliedDefault()) })
    }

    try {
      await (ctx.session as any).hook("experimental.model.resolve", async (event: any) => {
        const providerID = String(event.model?.providerID ?? "")
        const id = String(event.model?.id ?? "")
        if (!providerID || !id) return
        const map = loadMap()
        const tier = map?.agents?.[event.agent as string]
        const override = map?.overrides?.[String(event.agent)]?.[providerID]
        const spec = override ?? (tier ? map?.tiers?.[tier]?.[providerID] : undefined)

        if (tier && spec) {
          const models = await catalog()
          const wanted = parseSpec(spec)
          const resolved = models.length ? resolveSpec(spec, providerID, models) : { providerID, id: wanted.id }
          if (resolved) {
            event.model = {
              providerID: resolved.providerID,
              id: resolved.id,
              ...(resolved.variant ? { variant: resolved.variant } : {}),
            }
            logOnce(String(event.agent), {
              event: "resolve",
              reason: models.length
                ? override
                  ? "override"
                  : wanted.variant && !resolved.variant
                    ? "tier-variant-dropped"
                    : "tier"
                : "catalog-empty",
              providerID: resolved.providerID,
              id: resolved.id,
              variant: resolved.variant ?? null,
            })
            return
          }
          logOnce(String(event.agent), { event: "resolve", reason: "inherit-no-match", providerID, id })
          return
        }

        if (tier) {
          logOnce(String(event.agent), { event: "resolve", reason: "inherit-no-column", providerID, id })
          return
        }

        if (event.kind === "primary" && (current?.providerID !== providerID || current?.id !== id)) {
          current = { providerID, id }
          await ctx.storage.set("lastModel", current)
          await (ctx.model as any).reload()
          log({ event: "sticky-default", providerID, id, ...(await appliedDefault()) })
        }
      })
      log({ event: "hook-registered" })
    } catch {
      log({ event: "hook-missing" })
    }
  },
})
