---
name: jira
description: Draft a Jira story or incident writeup
---
Write a Jira story/writeup about the topic the user asked for in this turn. If the topic is missing, ask for it. Keep the format below exactly.

Format (exactly these three parts, nothing else):

```
# Short but descriptive title - <service-or-project-name>

## Description
<the problem or need, and the verified context>

## Proposal
<what to change or build>
```

Rules:
- No other sections. No acceptance criteria, PR references, links, or cross-references to other stories.
- State only facts verified in this session (root cause, fix, evidence). Never invent rationale, context, or pipeline/system names not confirmed.
- If a claim is unverified, ask me before you put it in the story.
- Concise. Use Simplified Technical English. No filler prose.
- Use `-` instead of em-dashes.
- Do NOT hard-wrap lines; Jira renders literal breaks. One paragraph or bullet = one line.
- One unified scope per story. If I ask for several stories, write each one self-contained in the same .md file.
- Save the draft as a .md file under the current project path. If no repo is in scope, output it in a single fenced block.
