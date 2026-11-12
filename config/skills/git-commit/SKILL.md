---
name: git-commit
description: >
    Commit message conventions and git commit execution rules. MUST be loaded
    before running any git commit command. Invoke whenever the user asks to
    commit changes, stage files, or create a commit — even without an
    explicit slash command.
---

# Git Commits

Use Conventional Commits. Every commit message must follow this format:

```
<type>(<scope>): <short description>
```

---

## Types

| Type       | When to use                                             |
| ---------- | ------------------------------------------------------- |
| `feat`     | New functionality                                       |
| `fix`      | Bug fix                                                 |
| `refactor` | Code change that neither adds a feature nor fixes a bug |
| `chore`    | Maintenance — dependencies, config, tooling             |
| `test`     | Adding or updating tests                                |
| `docs`     | Documentation only                                      |

## Scope

The scope is the part of the codebase affected. Keep it to one word. Derive it from
this repo's own naming — the actual directory, module, package, or service name the
change touches (e.g. a top-level folder name, a package name, a service name already
used in the codebase). Don't impose vocabulary from another project.

Common cross-cutting scopes, when the change doesn't map to one module:
`deps`, `config`, `ci`, `docs`.

Scope is optional only when the change is truly cross-cutting across multiple modules.

---

## Short Description

- Lowercase, no period at the end
- Imperative mood: "add retry logic" not "added retry logic"
- Max ~70 characters
- Enough context to understand the change without reading the diff

---

## Examples

```
feat(api): add payload validation on ingestion
fix(auth): handle expired tokens without crashing
refactor(worker): extract batch processing into private method
chore(deps): add pytest-mock as dev dependency
test(api): add unit tests for json payload loading
docs(config): document required environment variables
chore(deps): upgrade requests to 2.32.0
```

---

## Grouping and Executing Commits

When multiple files have been changed, never commit everything in a single `git add .`.
Group changes by concern and make one commit per group.

**How to group:**

1. List all changed files with `git status`
2. Identify logical groups — each group should map to a single type + scope
3. Commit each group separately in order from most foundational to most dependent
   (e.g. shared/lower-level modules before the code that consumes them, deps before
   code that uses them)

**Execution per group:**

```bash
git add <file1> <file2> ...
git commit -m "<type>(<scope>): <description>"
```

**Example — adding a new module and wiring it into an existing one:**

```bash
# Group 1: new module
git add lib/rate_limiter.py
git commit -m "feat(lib): add rate limiter"

# Group 2: consumer wired up
git add api/handler.py
git commit -m "feat(api): apply rate limiter to incoming requests"
```

**Rules:**

- Never use `git add .` or `git add -A`
- If a file genuinely touches multiple concerns, prefer the dominant one as the scope
- `pyproject.toml` and `uv.lock` always go together in a single `chore(deps)` commit
- Never include Claude as co-author
- Never push changes — only commit when asked

---

## What to Avoid

```
# Too vague
fix: bug fix
chore: changes
feat: stuff

# Not imperative
feat(api): added image download support

# Unnecessary detail (that's what the diff is for)
fix(worker): changed line 42 in worker.py to fix the null check
```
