/**
 * shepherd for OpenCode.
 *
 * Ports the Claude Code plugin hooks to the OpenCode V2 plugin API:
 *   SessionStart      -> the session prompt hook injects branch state once
 *   PreToolUse (Bash)  -> the permission evaluate hook gates git push / gh pr merge
 *   PreToolUse (Edit)  -> the permission evaluate hook keeps an active diagnosis read-only
 *   Stop               -> session.idle re-queues the next step while a phase is active
 *
 * State lives in <repo>/.opencode/shepherd/<branch>/ and is written by the
 * `shepherd` CLI. This plugin only reads it, except for the stop-block counter.
 */

import { Plugin } from "@opencode/plugin"
import { execFileSync } from "node:child_process"
import { existsSync, readFileSync, realpathSync, writeFileSync, renameSync } from "node:fs"
import { dirname, isAbsolute, join, resolve } from "node:path"

const ACTIVE_PHASES = ["study", "implement", "review", "push", "triage"]
const MAX_STOP_BLOCKS = 3

const NEXT_STEP: Record<string, string> = {
  study:
    "finish the brief and the plan, then implement (or, if the task is complex, run the plan design review and ask the user to approve or revise the plan)",
  implement: "finish the change, run the targeted checks, commit, then run the review gate",
  review:
    "triage the reviewer's findings, fix and commit, then re-review within budget, run the verify call when the budget is spent, or clear the tree",
  push: "push the cleared commit, then start the CI watch in the background and set phase=waiting_ci",
  triage: "answer or fix every open comment, then push or move to waiting_review / done",
}

type Json = Record<string, any>

function git(args: string[], cwd: string): string | undefined {
  try {
    return execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim()
  } catch {
    return undefined
  }
}

function repoRoot(cwd: string): string | undefined {
  return git(["rev-parse", "--show-toplevel"], cwd) || undefined
}

function currentBranch(cwd: string): string | undefined {
  return git(["rev-parse", "--abbrev-ref", "HEAD"], cwd) || undefined
}

function stateDir(cwd: string): string | undefined {
  const root = repoRoot(cwd)
  const branch = currentBranch(cwd)
  if (!root || !branch) return undefined
  return join(root, ".opencode", "shepherd", branch.replaceAll("/", "__"))
}

function readJson(path: string): Json | undefined {
  try {
    return JSON.parse(readFileSync(path, "utf8")) as Json
  } catch {
    return undefined
  }
}

function readState(cwd: string): Json | undefined {
  const dir = stateDir(cwd)
  if (!dir) return undefined
  return readJson(join(dir, "state.json"))
}

function diagnoseFile(cwd: string): string | undefined {
  const root = repoRoot(cwd)
  if (!root) return undefined
  return join(root, ".opencode", "shepherd", "_diagnose", "active.json")
}

function diagnoseActive(cwd: string): Json | undefined {
  const file = diagnoseFile(cwd)
  if (!file || !existsSync(file)) return undefined
  return readJson(file)
}

function bumpStopBlocks(cwd: string): number {
  const dir = stateDir(cwd)
  if (!dir) return MAX_STOP_BLOCKS
  const file = join(dir, "state.json")
  const state = readJson(file)
  if (!state) return MAX_STOP_BLOCKS
  const next = Number(state.stop_blocks ?? 0) + 1
  state.stop_blocks = next
  state.updated_at = new Date().toISOString().replace(/\.\d+Z$/, "Z")
  const tmp = `${file}.tmp.${process.pid}`
  writeFileSync(tmp, JSON.stringify(state, null, 2))
  renameSync(tmp, file)
  return next
}

function physical(path: string, cwd: string): string {
  let target = isAbsolute(path) ? path : resolve(cwd, path)
  let rest = ""
  while (!existsSync(target) && dirname(target) !== target) {
    rest = `/${target.split("/").pop()}${rest}`
    target = dirname(target)
  }
  try {
    return realpathSync(target) + rest
  } catch {
    return target + rest
  }
}

function shellCommand(input: Json): string {
  return String(input.command ?? input.cmd ?? input.script ?? "")
}

function editedPath(input: Json): string {
  return String(input.filePath ?? input.file_path ?? input.path ?? input.notebookPath ?? input.notebook_path ?? "")
}

function isShell(tool: string): boolean {
  return /^(shell|bash|sh|terminal)$/i.test(tool)
}

function isEdit(tool: string): boolean {
  return /^(edit|write|patch|multiedit|multi_edit|apply_patch|notebookedit)$/i.test(tool)
}

function deny(message: string): never {
  throw new Error(message)
}

const PUSH_RE = /(^|[;&|(])\s*git\s+([^;&|]*\s)?push(\s|$)/
const MERGE_RE = /(^|[;&|(])\s*gh\s+pr\s+merge(\s|$)/
const FORCE_RE = /\s(-f|--force|--force-with-lease[^\s]*)(\s|$)/
const GIT_STATE_RE =
  /(^|[;&|(])\s*git\s+([^;&|]*\s)?(commit|switch|checkout|push|merge|rebase|reset|stash|cherry-pick|revert|am|apply|restore|rm|mv|branch\s+-[mMdD])(\s|$)/
const GH_STATE_RE = /(^|[;&|(])\s*gh\s+pr\s+(create|merge|edit|comment|review)(\s|$)/

export default Plugin.define({
  id: "shepherd",
  async setup(ctx) {
    const seenSessions = new Set<string>()

    // ── PreToolUse: pre-push gate and diagnose guard ─────────────────────
    await ctx.permission.hook("evaluate", (event) => {
      const cwd = ctx.location.directory

      if (event.action === "shell") {
        const commands = event.resources.map(String)
        const state = readState(cwd)
        const diag = diagnoseActive(cwd)

        for (const cmd of commands) {
          if (diag) {
            if (GIT_STATE_RE.test(cmd) || GH_STATE_RE.test(cmd)) {
              event.effect = "deny"
              event.message = `shepherd diagnose: '${diag.slug}' is active. This command changes git or PR state. Diagnose only. Put probes in ${diag.scratch}. To fix, run \`shepherd diagnose end\` and start /shepherd/run ${diag.writeup} in a new session.`
              return
            }
          }

          if (!state) continue
          if (!PUSH_RE.test(cmd) && !MERGE_RE.test(cmd)) continue

          if (MERGE_RE.test(cmd)) {
            event.effect = "deny"
            event.message = "shepherd: never merge a shepherd PR. Set phase=done and hand the PR back to the user."
            return
          }

          if (FORCE_RE.test(cmd)) {
            event.effect = "deny"
            event.message =
              "shepherd: never force-push a shepherd branch. Push follow-up commits so earlier reviews stay valid."
            return
          }

          try {
            const dirty = execFileSync("git", ["status", "--porcelain", "--untracked-files=no"], {
              cwd,
              encoding: "utf8",
              stdio: ["ignore", "pipe", "ignore"],
            }).trim()
            if (dirty) {
              event.effect = "deny"
              event.message =
                "shepherd: the worktree has uncommitted changes. Commit the exact state you reviewed, then push."
              return
            }
            const headTree = git(["rev-parse", "HEAD^{tree}"], cwd)
            const cleared = String(state.cleared_tree ?? "")
            if (!headTree || headTree !== cleared) {
              event.effect = "deny"
              event.message = `shepherd: HEAD tree ${headTree ?? "unknown"} is not cleared (cleared: ${cleared || "none"}). Run the review gate, or record an exempt delta with \`shepherd clear --exempt <class> --reason <why>\`, then push.`
              return
            }
          } catch {
            // If git cannot answer, do not turn a broken repo into a push.
            event.effect = "deny"
            event.message = "shepherd: could not verify the worktree state, so the push is blocked."
            return
          }
        }
        return
      }

      if (event.action === "edit" || event.action === "write" || event.action === "patch") {
        const diag = diagnoseActive(cwd)
        if (!diag) return
        const root = repoRoot(cwd)
        if (!root) return
        const writeup = physical(String(diag.writeup), root)
        const scratch = physical(String(diag.scratch), root)
        for (const resource of event.resources.map(String)) {
          const target = physical(resource, cwd)
          if (!target.startsWith(root + "/")) continue
          if (target === writeup) continue
          if (target.startsWith(join(root, "docs", "diagnoses") + "/")) continue
          if (target.startsWith(scratch + "/")) continue
          event.effect = "deny"
          event.message = `shepherd diagnose: editing ${target} is blocked. Diagnosis '${diag.slug}' is active: diagnose only. Put probes in ${diag.scratch}. To fix, run \`shepherd diagnose end\` and start /shepherd/run ${diag.writeup} in a new session.`
          return
        }
      }
    })

    // ── SessionStart: resume state on the first prompt of a session ──────
    await ctx.session.hook("prompt", async (event) => {
      const sessionID = String((event as any).sessionID ?? "")
      if (sessionID) {
        try {
          if ((await ctx.session.get({ sessionID }))?.parentID) return
        } catch {
          // If the session cannot be read, treat it as a root session.
        }
      }
      if (sessionID && seenSessions.has(sessionID)) return
      if (sessionID) {
        seenSessions.add(sessionID)
        if (seenSessions.size > 200) seenSessions.delete(seenSessions.values().next().value as string)
      }

      const cwd = ctx.location.directory
      const parts: string[] = []

      const diag = diagnoseActive(cwd)
      if (diag) {
        parts.push(
          `A shepherd diagnosis is active in this worktree (write-up: ${diag.writeup}). Edits outside the write-up and its scratch dir are blocked. Resume it with the /shepherd/diagnose skill; read the write-up first.`,
        )
      }

      const state = readState(cwd)
      if (state && state.phase !== "done") {
        const dir = stateDir(cwd)
        const brief = dir && existsSync(join(dir, "brief.md")) ? readFileSync(join(dir, "brief.md"), "utf8") : ""
        const decisions = dir && existsSync(join(dir, "decisions.md")) ? readFileSync(join(dir, "decisions.md"), "utf8") : ""
        parts.push(
          `shepherd is active on this branch (phase: ${state.phase}). Resume it with the /shepherd/run skill before doing anything else on this branch. State dir: ${dir}\n\n## state.json\n${JSON.stringify(state, null, 2)}\n\n## brief.md\n${brief}\n\nRead ${dir}/decisions.md before you change direction on anything it records.\n\n## decisions.md\n${decisions}`,
        )
      }

      if (!parts.length) return
      const block = `\n\n<shepherd-context>\n${parts.join("\n\n")}\n</shepherd-context>`
      event.prompt.text = `${event.prompt.text}${block}`
    })

    // ── Stop: re-queue the next step while a phase is active ─────────────
    const controller = new AbortController()
    void (async () => {
      try {
        for await (const raw of ctx.event.subscribe({ types: ["session.idle"], signal: controller.signal })) {
          const event = raw as any
          const sessionID =
            event.properties?.sessionID ?? event.properties?.session?.id ?? event.sessionID ?? event.session?.id
          if (!sessionID) continue
          try {
            if ((await ctx.session.get({ sessionID }))?.parentID) continue
          } catch {
            // If the session cannot be read, treat it as a root session.
          }

          const cwd = ctx.location.directory
          const state = readState(cwd)
          if (!state || !ACTIVE_PHASES.includes(String(state.phase))) continue

          const blocks = bumpStopBlocks(cwd)
          if (blocks > MAX_STOP_BLOCKS) continue

          const phase = String(state.phase)
          const next = NEXT_STEP[phase] ?? "continue the shepherd loop"
          await ctx.session.prompt({
            sessionID,
            delivery: "queue",
            text: `<shepherd-stop-block>\nshepherd phase is '${phase}'; the loop is not at a stopping point. Next: ${next}. If you need the user, set phase=waiting_user and ask one question. If the work is complete, set phase=done.\n</shepherd-stop-block>`,
          })
        }
      } catch {
        // Aborted on unload.
      }
    })()

    return () => controller.abort()
  },
})
