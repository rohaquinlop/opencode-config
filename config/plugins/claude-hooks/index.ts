/**
 * claude-config hooks, ported to OpenCode.
 *
 *   PreToolUse (Bash)  -> deny destructive / branch-creating git ops
 *   PostToolUse (Edit) -> run ruff, ty, complexipy on changed Python files and
 *                         add the failures to the next model request
 *   Stop               -> run the Python quality gate on uncommitted .py changes
 *                         and push the agent to fix it, at most 3 times per tree
 *
 * The herdr session reporter and the Claude status line have no OpenCode
 * equivalent and are intentionally not ported.
 */

import { Plugin } from "@opencode/plugin"
import { execFileSync } from "node:child_process"
import { existsSync, readFileSync } from "node:fs"
import { dirname, join, resolve } from "node:path"
import { createHash } from "node:crypto"

const DESTRUCTIVE_RE = /(^|[;&|(])\s*git\s+(reset\s+--hard|checkout\s+-b|switch\s+-c)(\s|$)/
const MAX_GATE_ATTEMPTS = 3

function has(cmd: string): boolean {
  try {
    execFileSync("which", [cmd], { stdio: "ignore" })
    return true
  } catch {
    return false
  }
}

function run(
  cmd: string,
  args: string[],
  cwd: string,
  timeout = 120_000,
): { ok: boolean; code: number; out: string } {
  try {
    const out = execFileSync(cmd, args, {
      cwd,
      encoding: "utf8",
      timeout,
      stdio: ["ignore", "pipe", "pipe"],
      env: { ...process.env, FORCE_COLOR: "0", NO_COLOR: "1", CLICOLOR: "0", TERM: "dumb" },
    })
    return { ok: true, code: 0, out: out ?? "" }
  } catch (error: any) {
    const out = `${error?.stdout ?? ""}${error?.stderr ?? ""}` || String(error?.message ?? error)
    return { ok: false, code: Number(error?.status ?? 1), out }
  }
}

function projectFor(file: string, fallback: string): string | undefined {
  let dir = dirname(resolve(file))
  const stop = resolve(fallback)
  for (;;) {
    if (existsSync(join(dir, "pyproject.toml"))) return dir
    if (dir === stop || dir === dirname(dir)) break
    dir = dirname(dir)
  }
  return existsSync(join(stop, "pyproject.toml")) ? stop : undefined
}

function editedPath(input: any): string {
  return String(input?.filePath ?? input?.file_path ?? input?.path ?? "")
}

function isPython(path: string): boolean {
  return /\.pyi?$/.test(path)
}

export default Plugin.define({
  id: "claude-hooks",
  async setup(ctx) {
    const pending = new Map<string, string[]>()
    const sessionFor = (event: any) => String(event?.sessionID ?? event?.properties?.sessionID ?? "*")

    // ── PreToolUse: destructive git ──────────────────────────────────────
    await ctx.permission.hook("evaluate", (event) => {
      if (event.action !== "shell") return
      for (const command of event.resources.map(String)) {
        if (DESTRUCTIVE_RE.test(command)) {
          event.effect = "deny"
          event.message =
            "Blocked: ask the user before destructive or branch-creating git ops (git reset --hard, git checkout -b, git switch -c)."
          return
        }
      }
    })

    // ── PostToolUse: Python checks on edit/write ─────────────────────────
    await ctx.tool.hook("execute.after", (event) => {
      if (event.status !== "completed") return
      if (!/^(edit|write|patch|multiedit|multi_edit|apply_patch)$/i.test(event.tool)) return

      const path = editedPath((event as any).input)
      if (!path || !isPython(path)) return
      const project = projectFor(path, ctx.location.directory)
      if (!project) return

      const report: string[] = []
      const check = (name: string, cmd: string, args: string[]) => {
        if (has(cmd)) {
          const result = run(cmd, args, project)
          if (!result.ok) report.push(`== ${name} failed ==\n${result.out.trim()}`)
          return
        }
        if (has("uvx")) {
          const result = run("uvx", [cmd, ...args], project)
          if (!result.ok) report.push(`== ${name} failed ==\n${result.out.trim()}`)
        }
      }

      check("ruff", "ruff", ["check", "--force-exclude", "-q", path])
      check("ty", "ty", ["check", "--force-exclude", path])
      check("complexipy", "complexipy", ["--failed", "--plain", path])

      if (!report.length) return
      const sessionID = sessionFor(event)
      const list = pending.get(sessionID) ?? []
      list.push(`Checks on ${path}:\n${report.join("\n\n")}`)
      pending.set(sessionID, list)
      if (pending.size > 50) pending.delete(pending.keys().next().value as string)
    })

    // ── PostToolUse context: deliver check failures on the next request ──
    await ctx.session.hook("context", (event) => {
      const reports = [...(pending.get(event.sessionID) ?? []), ...(pending.get("*") ?? [])]
      if (!reports.length) return
      pending.delete(event.sessionID)
      pending.delete("*")
      event.system.push({ type: "text", text: `<python-edit-checks>\n${reports.join("\n\n")}\n</python-edit-checks>` })
    })

    // ── Stop: Python quality gate ────────────────────────────────────────
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
          if (!existsSync(join(cwd, "pyproject.toml"))) continue

          const head = run("git", ["rev-parse", "--verify", "-q", "HEAD"], cwd)
          if (!head.ok) continue

          const tracked = run("git", ["diff", "--name-only", "--diff-filter=d", "HEAD", "--", "*.py"], cwd)
          const untracked = run("git", ["ls-files", "-o", "--exclude-standard", "--", "*.py"], cwd)
          const files = [...new Set(`${tracked.out}\n${untracked.out}`.split("\n").map((line) => line.trim()).filter(Boolean))]
          if (!files.length) continue

          const diff = run("git", ["diff", "HEAD"], cwd)
          const contents = files
            .map((file) => {
              try {
                return readFileSync(join(cwd, file), "utf8")
              } catch {
                return ""
              }
            })
            .join("\n")
          const tree = createHash("sha1").update(`${diff.out}\n${contents}`).digest("hex")

          const key = `pygate/${createHash("sha1").update(cwd).digest("hex")}`
          const saved: any = (await ctx.storage.get(key)) ?? {}
          if (saved.passed === tree || saved.reported === tree) continue
          const attempts = saved.tree === tree ? Number(saved.attempts ?? 0) : 0
          if (attempts >= MAX_GATE_ATTEMPTS) {
            await ctx.storage.set(key, { ...saved, tree, reported: tree, attempts })
            continue
          }

          const report: string[] = []
          const check = (name: string, cmd: string, args: string[], timeout?: number) => {
            if (has(cmd)) {
              const result = run(cmd, args, cwd, timeout)
              if (!result.ok) report.push(`== ${name} failed ==\n${result.out.trim()}`)
              return
            }
            if (has("uvx")) {
              const result = run("uvx", [cmd, ...args], cwd, timeout)
              if (!result.ok) report.push(`== ${name} failed ==\n${result.out.trim()}`)
            }
          }

          const pytest = run("uv", ["run", "--no-sync", "pytest", "-q", "-x"], cwd, 900_000)
          if (!pytest.ok && pytest.code !== 5) report.push(`== pytest failed ==\n${pytest.out.trim()}`)
          check("complexipy", "complexipy", ["--failed", "--plain", ...files])
          check("jscpd", "npx", ["-y", "jscpd@4", "--min-lines", "5", "--threshold", "3", "--reporters", "console", ...files])

          if (!report.length) {
            await ctx.storage.set(key, { tree, passed: tree, attempts: 0 })
            continue
          }

          await ctx.storage.set(key, { tree, attempts: attempts + 1 })
          const docker = run("docker", ["ps", "--format", "{{.Names}}"], cwd, 10_000)
          const containers = docker.ok ? docker.out.trim() : ""
          const warning = containers ? `\n\nWARNING: containers still running:\n${containers}` : ""
          await ctx.session.prompt({
            sessionID,
            delivery: "queue",
            text: `<python-quality-gate>\nQuality gate failed. Fix these before you finish:\n${report.join("\n\n")}${warning}\n</python-quality-gate>`,
          })
        }
      } catch {
        // Aborted on unload.
      }
    })()

    return () => controller.abort()
  },
})
