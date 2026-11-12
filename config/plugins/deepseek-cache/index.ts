/**
 * deepseek-cache for OpenCode.
 *
 * Port of pi-deepseek-cache. DeepSeek and MiMo bill cached prefix tokens at
 * 50–120x less than fresh input, but only when the prompt prefix is
 * byte-identical from position 0.
 *
 *   P0  Freeze the date and environment system parts for the session.
 *   P1  Per-session hit-rate telemetry, exposed as the cache_stats tool.
 *   P2  Prefix guard: hash the prefix each turn and count breaks.
 *   P3  Deterministic compaction at temperature 0, with a summary cache.
 *
 * OpenRouter upstream pinning (P5 in the Pi extension) is not ported: it needs
 * OpenRouter-specific routing state. Use the `deepseek` provider directly.
 */

import { Plugin } from "@opencode/plugin"
import { createHash } from "node:crypto"

const FAMILY_RE = /(^|\/)(deepseek|mimo)(-|$)/i
const SUMMARY_MAX_CHARS = 120_000

type ModelRef = { providerID: string; id: string }
type Stats = {
  input: number
  cacheRead: number
  cacheWrite: number
  turns: number
  model?: ModelRef
  breaks: number
  history: { turn: number; hitRate: number }[]
  updated: number
}

function isCacheOptimized(model: ModelRef | undefined): boolean {
  if (!model) return false
  return FAMILY_RE.test(model.id) || model.providerID === "deepseek" || /^xiaomi/.test(model.providerID)
}

function hitRate(cacheRead: number, input: number, cacheWrite: number): number {
  const total = cacheRead + input + cacheWrite
  return total > 0 ? (cacheRead / total) * 100 : 0
}

function sha256(text: string): string {
  return createHash("sha256").update(text).digest("hex")
}

function emptyStats(): Stats {
  return { input: 0, cacheRead: 0, cacheWrite: 0, turns: 0, breaks: 0, history: [], updated: Date.now() }
}

function fmt(n: number): string {
  return n.toLocaleString("en-US")
}

function money(n: number): string {
  if (n <= 0) return "$0.00"
  return n < 0.01 ? "< $0.01" : `$${n.toFixed(2)}`
}

function priceOf(model: any): { input: number; cacheRead: number } | undefined {
  const tier = model?.cost?.[0]
  if (!tier) return undefined
  return { input: Number(tier.input ?? 0), cacheRead: Number(tier.cache?.read ?? 0) }
}

// models.dev pricing is not always present for a provider. These are the
// published DeepSeek/MiMo list prices per million input tokens.
function fallbackPrice(model: ModelRef | undefined): { input: number; cacheRead: number } | undefined {
  if (!isCacheOptimized(model)) return undefined
  return model!.id.toLowerCase().includes("pro")
    ? { input: 0.435, cacheRead: 0.003625 }
    : { input: 0.14, cacheRead: 0.0028 }
}

export default Plugin.define({
  id: "deepseek-cache",
  async setup(ctx) {
    // sessionID -> system-part key -> frozen text
    const frozen = new Map<string, Map<string, string>>()
    // sessionID -> last prefix hash / break count
    const prefixes = new Map<string, { hash?: string; breaks: number }>()

    async function computeStats(sessionID: string): Promise<Stats> {
      const stats = emptyStats()
      const guard = prefixes.get(sessionID)
      stats.breaks = guard?.breaks ?? 0

      let messages: readonly any[] = []
      try {
        messages = await ctx.session.context({ sessionID })
      } catch {
        return stats
      }

      let lastRate = 0
      for (const message of messages) {
        if (message?.type !== "assistant" || !message.tokens) continue
        const t = message.tokens
        stats.cacheRead += Number(t.cache?.read ?? 0)
        stats.cacheWrite += Number(t.cache?.write ?? 0)
        stats.input += Number(t.input ?? 0)
        stats.turns += 1
        if (message.model) stats.model = { providerID: message.model.providerID, id: message.model.id }

        const rate = hitRate(stats.cacheRead, stats.input, stats.cacheWrite)
        if (Math.round(rate * 100) !== Math.round(lastRate * 100)) {
          stats.history.push({ turn: stats.turns, hitRate: rate })
          lastRate = rate
        }
      }

      stats.updated = Date.now()
      return stats
    }

    async function saveStats(sessionID: string): Promise<Stats> {
      const stats = await computeStats(sessionID)
      try {
        await ctx.storage.set(`stats/${sessionID}`, stats)
      } catch {
        // best effort
      }
      return stats
    }

    async function loadAll(): Promise<{ sessionID: string; stats: Stats }[]> {
      try {
        const page = await ctx.storage.scan({ prefix: "stats/", limit: 1000 })
        return page.entries.map((entry) => ({
          sessionID: entry.key.slice("stats/".length),
          stats: entry.value as Stats,
        }))
      } catch {
        return []
      }
    }

    type Price = { input: number; cacheRead: number }

    function savings(stats: Stats, price: Price | undefined): number {
      if (!price) return 0
      const delta = Math.max(0, price.input - price.cacheRead)
      return (stats.cacheRead / 1_000_000) * delta
    }

    function renderStats(
      current: Stats,
      all: { sessionID: string; stats: Stats }[],
      price: Price | undefined,
      priceFor: (stats: Stats) => Price | undefined,
    ): string {
      const rate = hitRate(current.cacheRead, current.input, current.cacheWrite)

      const lines: string[] = [
        "Cache — this session",
        `  hit rate      ${rate.toFixed(1)}%`,
        `  cache hits    ${fmt(current.cacheRead)} tokens`,
      ]
      if (current.cacheWrite > 0) lines.push(`  cache writes  ${fmt(current.cacheWrite)} tokens`)
      lines.push(
        `  cache misses  ${fmt(current.input)} tokens`,
        `  turns         ${current.turns}`,
        `  prefix breaks ${current.breaks}`,
      )
      if (price) lines.push(`  est. savings  ${money(savings(current, price))}`)

      if (all.length > 1) {
        let input = 0
        let cacheRead = 0
        let cacheWrite = 0
        let turns = 0
        let saved = 0
        for (const entry of all) {
          input += entry.stats.input ?? 0
          cacheRead += entry.stats.cacheRead ?? 0
          cacheWrite += entry.stats.cacheWrite ?? 0
          turns += entry.stats.turns ?? 0
          saved += savings(entry.stats, priceFor(entry.stats))
        }
        lines.push(
          "",
          `All sessions (${all.length})`,
          `  hit rate      ${hitRate(cacheRead, input, cacheWrite).toFixed(1)}%`,
          `  cache hits    ${fmt(cacheRead)} tokens`,
          `  cache misses  ${fmt(input)} tokens`,
          `  turns         ${turns}`,
          `  est. savings  ${money(saved)}`,
        )
      }
      return lines.join("\n")
    }

    // ── P0: freeze date and environment per session ──────────────────────
    // ── P2: prefix hash per turn ─────────────────────────────────────────
    await ctx.session.hook("context", (event) => {
      const model = { providerID: event.model.providerID, id: event.model.id }
      if (!isCacheOptimized(model)) return

      const sessionID = event.sessionID

      // P0: capture the first rendering of each dynamic instruction source and
      // force it on every later request. Byte-identical prefix, same session.
      let sessionFrozen = frozen.get(sessionID)
      if (!sessionFrozen) {
        sessionFrozen = new Map()
        frozen.set(sessionID, sessionFrozen)
        if (frozen.size > 200) frozen.delete(frozen.keys().next().value as string)
      }
      for (const part of event.system as any[]) {
        const sources = part?.metadata?.experimental?.instructions
        if (!Array.isArray(sources)) continue
        for (const source of sources) {
          if (!source || (source.key !== "core/date" && source.key !== "core/environment")) continue
          const text = String(source.text ?? "")
          if (!text) continue
          if (!sessionFrozen.has(source.key)) sessionFrozen.set(source.key, text)
          const frozenText = sessionFrozen.get(source.key)!
          if (part.text === text) part.text = frozenText
          else if (typeof part.text === "string") part.text = part.text.replace(text, frozenText)
        }
      }

      // P2: everything before the current turn is the cacheable prefix.
      const messages = event.messages as any[]
      if (messages.length > 1) {
        const hash = sha256(JSON.stringify(messages.slice(0, -1)))
        const guard = prefixes.get(sessionID) ?? { breaks: 0 }
        if (guard.hash !== undefined && guard.hash !== hash) guard.breaks += 1
        guard.hash = hash
        prefixes.set(sessionID, guard)
        if (prefixes.size > 200) prefixes.delete(prefixes.keys().next().value as string)
      }
    })

    // ── P3: deterministic compaction at temperature 0 ────────────────────
    await ctx.session.hook("compaction", async (event) => {
      const model = { providerID: event.model.providerID, id: event.model.id }
      if (!isCacheOptimized(model)) return
      event.options.temperature = 0

      const generate = (ctx as any).experimental?.generate?.text ?? (ctx as any).generate?.text
      if (typeof generate !== "function") return

      try {
        const transcript = JSON.stringify(event.messages).slice(0, SUMMARY_MAX_CHARS)
        const prompt =
          "Summarize this conversation history into structured markdown. Cover: 1 goal 2 key decisions and rationale 3 code/file changes 4 current progress 5 blockers and open questions 6 next steps. Be thorough - this summary replaces the original history.\n\n" +
          transcript
        const summarizer = model.id.includes("pro") ? { providerID: model.providerID, id: "deepseek-flash" } : model
        const key = `summary/${sha256(`${summarizer.providerID}/${summarizer.id}\n${prompt}`)}`
        const cached = await ctx.storage.get(key)
        if (typeof cached === "string" && cached.trim()) {
          event.result = { summary: cached }
          return
        }
        const response = await generate({ model: summarizer, prompt })
        const summary = String(response?.text ?? "").trim()
        if (summary) {
          event.result = { summary }
          await ctx.storage.set(key, summary)
        }
      } catch {
        // Fall back to OpenCode's own compaction.
      }
    })

    // ── P1: store stats when a session goes idle ─────────────────────────
    const controller = new AbortController()
    void (async () => {
      try {
        for await (const raw of ctx.event.subscribe({ types: ["session.idle"], signal: controller.signal })) {
          const event = raw as any
          const sessionID =
            event.properties?.sessionID ?? event.properties?.session?.id ?? event.sessionID ?? event.session?.id
          if (sessionID) void saveStats(String(sessionID))
        }
      } catch {
        // Aborted on unload.
      }
    })()

    // ── Tools ────────────────────────────────────────────────────────────
    await ctx.tool.transform((editor) => {
      editor.add({
        name: "cache_stats",
        description:
          "Show DeepSeek/MiMo prefix-cache hit rate, cached tokens, misses, turns, and prefix breaks for this session and across all sessions.",
        input: { type: "object", properties: {}, additionalProperties: false },
        execute: async (_input, context: any) => {
          const sessionID = String(context?.sessionID ?? "")
          const current = sessionID ? await saveStats(sessionID) : emptyStats()
          const all = await loadAll()

          const priceByModel = new Map<string, Price>()
          try {
            for (const model of await ctx.model.list()) {
              const p = priceOf(model)
              if (p) priceByModel.set(`${model.providerID}/${model.id}`, p)
            }
          } catch {
            // pricing is optional
          }
          const key = (stats: Stats) => (stats.model ? `${stats.model.providerID}/${stats.model.id}` : "")
          const priceFor = (stats: Stats) => priceByModel.get(key(stats)) ?? fallbackPrice(stats.model)

          return { content: renderStats(current, all, priceFor(current), priceFor) }
        },
      })

      editor.add({
        name: "cache_graph",
        description: "Show an ASCII chart of this session's cache hit rate over turns.",
        input: { type: "object", properties: {}, additionalProperties: false },
        execute: async (_input, context: any) => {
          const sessionID = String(context?.sessionID ?? "")
          const stats = sessionID ? await computeStats(sessionID) : emptyStats()
          const points = stats.history
          if (points.length < 2) {
            return { content: "Need 2+ turns with cache data for a trend. Keep chatting and try again." }
          }
          const step = Math.max(1, Math.floor(points.length / 44))
          const data = points.filter((_, index) => index % step === 0).slice(-44)
          const rates = data.map((p) => p.hitRate)
          const max = Math.max(...rates, 1)
          const min = Math.min(...rates, 0)
          const range = max - min || 1
          const height = 8
          const rows: string[] = []
          for (let r = height; r >= 0; r--) {
            const threshold = min + range * (r / height)
            const label =
              r === height ? `${max.toFixed(0)}%`.padStart(4) : r === 0 ? `${min.toFixed(0)}%`.padStart(4) : "    "
            rows.push(label + data.map((p) => (p.hitRate >= threshold ? "#" : " ")).join(""))
          }
          rows.push("    " + "-".repeat(data.length))
          const first = String(data[0].turn)
          const last = String(data[data.length - 1].turn)
          const mid = data.length > 2 ? String(data[Math.floor(data.length / 2)].turn) : ""
          const axis = new Array(data.length).fill(" ")
          for (let i = 0; i < first.length && i < axis.length; i++) axis[i] = first[i]
          if (mid) {
            const at = Math.floor((axis.length - mid.length) / 2)
            for (let i = 0; i < mid.length; i++) if (at + i >= 0 && at + i < axis.length) axis[at + i] = mid[i]
          }
          for (let i = 0; i < last.length; i++) {
            const at = axis.length - last.length + i
            if (at >= 0 && at < axis.length) axis[at] = last[i]
          }
          rows.push("    " + axis.join(""))
          rows.push("    turn")
          return { content: `Cache hit rate over turns\n${rows.join("\n")}` }
        },
      })

      editor.add({
        name: "cache_reset",
        description: "Delete all stored cache statistics and summary cache entries.",
        input: { type: "object", properties: {}, additionalProperties: false },
        execute: async () => {
          for (const prefix of ["stats/", "summary/"]) {
            try {
              for (;;) {
                const page = await ctx.storage.scan({ prefix, limit: 1000 })
                if (!page.entries.length) break
                for (const entry of page.entries) await ctx.storage.remove(entry.key)
              }
            } catch {
              // best effort
            }
          }
          frozen.clear()
          prefixes.clear()
          return { content: "Cache statistics and summary cache cleared." }
        },
      })
    })
  },
})
