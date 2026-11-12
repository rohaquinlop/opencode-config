---
name: slack
description: Draft a terse Slack message for the team
---
Write a Slack message about the topic the user asked for in this turn. If the topic is missing, ask for it.

Rules:
- 3-6 lines max. No preamble, no sign-off, no emoji unless asked.
- Do NOT hard-wrap lines; Slack renders literal breaks.
- Only state facts you verified in this session. Mark anything unverified explicitly.
- Do not imply work is pending/unvalidated unless I confirmed that.
- Output the message in a single fenced block, nothing else.
