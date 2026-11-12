---
name: create-pr
description: >
    Create a GitHub Pull Request, or write a PR description, with title/body generated
    from the git diff. Supports optional target branch (defaults to main). MUST be loaded
    before creating or writing a PR description. Invoke whenever the user asks to create a
    PR, open a pull request, summarize branch changes, or submit changes via GitHub CLI.
---

# Create PR

Generates a PR title and body from `git diff`, writes it to `PR_DESCRIPTION.md`, then submits with `gh pr create`.

If the user only asks for a description (e.g. "summarize the branch changes", "write a PR description"), stop after step 1 of the workflow — write `PR_DESCRIPTION.md` and do not create the PR.

## Usage

The user may specify a target branch. If omitted, default is `main`.

Examples:
- "Create a PR" → targets `main`
- "Create a PR for staging" → targets `staging`
- "Create a PR against release-v2" → targets `release-v2`

## PR Description Format

When generating the PR description:

1. Run `git diff <base>...HEAD` (where `<base>` is the target branch) to see all changes on this branch.
2. Create or overwrite `PR_DESCRIPTION.md` in the repository root.
3. Write the PR description into `PR_DESCRIPTION.md` following the template below.
4. Final response must mention the file path and briefly summarize what was written.

Output requirements:

- MUST use the write tool to create or update `PR_DESCRIPTION.md`.
- MUST NOT only print the PR description in chat unless the user explicitly asks for chat-only output.
- If `PR_DESCRIPTION.md` was not written, the task is incomplete.

### Template

The file has two distinct sections — the title block and the body. The title is the first non-empty line after `## Title suggestion`. The body is everything from `## What` onwards.

```markdown
## Title suggestion

<short descriptive title here>

## What

One sentence explaining what this PR does.

## Why

Brief context on why this change is needed.

## Changes

- Bullet points of specific changes made
- Group related changes together
- Mention any files deleted or renamed
```

## Line wrapping — do not hard-wrap

GitHub renders **every single newline in a PR body as a literal `<br>`**. Hard-wrapped prose therefore displays with breaks mid-sentence, giving the description a ragged, "jumpy" look instead of clean full-width paragraphs.

Write each paragraph, bullet, and numbered item as **one unwrapped line**, however long it gets, and let GitHub do the wrapping.

- Do NOT wrap prose at 80 or 100 columns, even when the repo's code style does. That convention applies to code, not to PR bodies.
- One bullet = one line. No indented continuation lines underneath a bullet.
- Use blank lines only to separate blocks: between paragraphs, and around headings, lists, tables and code fences.
- Table rows are single lines already — keep them that way.
- Fenced code blocks are exempt; newlines inside them are literal and intended.

The same applies to anything else GitHub renders as user content: issue bodies, PR comments, and review comments.

Verify after posting, and expect `0`:

```bash
gh api repos/<owner>/<repo>/pulls/<n> \
  -H "Accept: application/vnd.github.html+json" --jq '.body_html' \
  | grep -o "<br>" | wc -l
```

## Scope — stick to the template

Describe what the PR does, and nothing else. Do not invent sections beyond the template above — no reviewer notes, editorial asides, self-assessment, or commentary on work deliberately left undone or out of scope.

If something like that seems worth saying, raise it with the user directly in conversation and let them decide whether it belongs in the PR.

## Workflow

1. **Generate the PR description** following the format above — run `git diff <target-branch>...HEAD`, then create `PR_DESCRIPTION.md` with the title and body.
2. **Determine target branch**: if user specified a branch, use that; otherwise `main`.
3. **Read `PR_DESCRIPTION.md`** to extract title and body:
   - **Title**: the first non-empty line after `## Title suggestion`. Do not include the header itself.
   - **Body**: everything from `## What` onwards (inclusive). This excludes the `## Title suggestion` block entirely.

   Extraction example:
   ```bash
   # Title: first non-empty line after "## Title suggestion"
   TITLE=$(sed -n '/^## Title suggestion/,/^##/{/^##/d;/^$/d;p;}' PR_DESCRIPTION.md | head -1)
   # Body: everything from "## What" to end of file
   BODY=$(sed -n '/^## What/,$p' PR_DESCRIPTION.md)
   ```
4. **Create PR via `gh pr create`**:

   ```bash
   gh pr create \
     --base <target-branch> \
     --title "$TITLE" \
     --body "$BODY"
   ```

   - If on a fork, add `--repo <owner>/<repo>` inferred from `git remote get-url origin`.
   - If the branch has no remote, prompt to push first with `git push -u origin HEAD`.
   - If `gh` is not authenticated, report error and stop.

5. **Verify line wrapping** with the `body_html` check above — expect `0`.
6. **Report result**: output the PR URL and a summary. Do NOT delete `PR_DESCRIPTION.md` — leave it for reference.

## Edge Cases

| Scenario | Action |
|----------|--------|
| No commits on branch vs base | Warn user: no diff to create PR from |
| Branch already has open PR | Detect with `gh pr list --head "$BRANCH"`; reuse or abort |
| Unpushed branch | Offer to push before creating PR |
| `gh` not installed | Report error, suggest `brew install gh` |
| `gh` not authenticated | Report error, suggest `gh auth login` |

## Parameter Detection

Parse the user's request for a target branch:

| Phrase | Branch |
|--------|--------|
| "for X" | X |
| "against X" | X |
| "into X" | X |
| "to X" | X |
| "base X" | X |
| No branch mention | `main` |
