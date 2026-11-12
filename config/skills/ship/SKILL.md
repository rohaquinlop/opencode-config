---
name: ship
description: Commit, check duplication, and open a PR
---
1. Run `git fetch` and show `git status`. Exclude backups, .env and secret-bearing files.
2. Ask me for the base branch (default: main) and the Jira key. Title format: `<JIRA-KEY>: <summary>`.
3. Run `uv run pytest` and `uv run ty check`. Fix any failures before continuing.
4. Run `npx jscpd --min-lines 5 $(git diff --name-only --diff-filter=d origin/$BASE)` and deduplicate anything it flags.
5. Group changes into small logical commits with conventional messages.
6. Run `gh pr create` and print the URL.
