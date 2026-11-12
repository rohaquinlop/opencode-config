/**
 * be-terse for OpenCode.
 *
 * Ports the Claude Code UserPromptSubmit hook: append a style instruction to
 * every prompt. Resolution order, first match wins:
 *   1. trailing "noterse"          -> add nothing, this prompt only
 *   2. trailing "ste"/"caveman"    -> that mode, this prompt only
 *   3. $BE_TERSE_MODE              -> session default
 *   4. saved mode                  -> last /be-terse/mode switch
 *   5. ste
 *
 * The saved mode lives in ${XDG_STATE_HOME:-~/.local/state}/be-terse/mode.
 */

import { Plugin } from "@opencode/plugin"
import { readFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const MODES = ["ste", "caveman"] as const
type Mode = (typeof MODES)[number]

const STE_CONTEXT = "respond tersely in Simplified Technical English"

const CAVEMAN_CONTEXT =
  "respond in caveman mode: ultra-compressed register, full technical accuracy. Drop articles, filler, pleasantries, hedging, and tool-call narration. Fragments are fine. Prefer short synonyms. Never invent abbreviations and never use arrows; they save no tokens. Never drop not/never/no/only/except. Keep numbers, units, technical terms, code blocks, and error strings exact. Compress only, never add words to sound caveman; if the caveman phrasing is not shorter, use plain phrasing. Do not name or announce the style. Drop caveman for security warnings, irreversible-action confirmations, and any place compression would create ambiguity. Write normal prose in anything that outlives the chat: code, comments, commit messages, docs, and issue or PR text."

function stateDir(): string {
  return join(process.env.XDG_STATE_HOME || join(homedir(), ".local", "state"), "be-terse")
}

function persistedMode(): string {
  try {
    return readFileSync(join(stateDir(), "mode"), "utf8").trim()
  } catch {
    return ""
  }
}

function isMode(value: string): value is Mode {
  return (MODES as readonly string[]).includes(value)
}

function trailing(text: string, keyword: string): boolean {
  return new RegExp(`(^|[\\s"])${keyword}[\\s\\r\\t]*$`).test(text)
}

export default Plugin.define({
  id: "be-terse",
  async setup(ctx) {
    await ctx.session.hook("prompt", async (event) => {
      const sessionID = String((event as any).sessionID ?? "")
      if (sessionID) {
        try {
          if ((await ctx.session.get({ sessionID }))?.parentID) return
        } catch {
          // If the session cannot be read, treat it as a root session.
        }
      }

      const text = event.prompt.text

      if (trailing(text, "noterse")) return

      let mode: string | undefined
      for (const candidate of MODES) {
        if (trailing(text, candidate)) {
          mode = candidate
          break
        }
      }

      if (!mode) mode = process.env.BE_TERSE_MODE || persistedMode()
      if (!mode || !isMode(mode)) mode = "ste"

      const instruction = mode === "caveman" ? CAVEMAN_CONTEXT : STE_CONTEXT
      event.prompt.text = `${text}\n\n${instruction}`
    })
  },
})
