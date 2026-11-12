---
name: poc-codebase-review
description: Review a codebase implementation against the PoC it was based on. Use when validating PR comments, behavior claims, parity gaps, regressions, or implementation differences between a production/service codebase and a proof-of-concept file, pipeline, notebook, or reference implementation. The user may provide PoC paths, a main entry point, target functions, reviewer comments, or domain notes.
---

# PoC Codebase Review

Use this skill to validate whether the current implementation matches the PoC behavior before proposing or making code changes.

## Required Inputs

Collect or infer:

- `poc_path`: file, directory, notebook, or script containing the reference PoC.
- `poc_entry_point`: main pipeline/function/class, if known.
- `current_path`: current implementation file/module, if known.
- `target`: function, behavior, PR comment, failing test, or suspected inconsistency.
- `user_context`: clarifications from the user about ownership, upstream/downstream contracts, expected behavior, or non-goals.

If one input is missing, search the repo first. Ask only when the missing input blocks validation.

## Workflow

1. **Frame The Claim**
   - Extract the exact behavior being questioned.
   - Separate questions from assertions.
   - Identify which part needs validation: data shape, call order, filtering, grouping, persistence, side effects, thresholds, or ownership boundary.

2. **Read The PoC First**
   - Open the provided PoC path.
   - Locate the target function and nearby helpers.
   - If a PoC entry point is provided, verify the pipeline actually calls the function.
   - Record call order and input/output shape from the real PoC path, not memory.

3. **Verify PoC Usage**
   - Confirm the PoC behavior is active in the execution path.
   - Check whether the function is used before/after relevant transforms.
   - Note if the PoC function exists but is unused, bypassed, or called with preprocessed data.

4. **Read Current Service**
   - Locate current code that implements the same behavior.
   - Trace upstream data construction and downstream consumers.
   - Check config defaults, payload contracts, side effects, batching, SQL calls, sorting, filtering, and edge cases.

5. **Compare Behavior**
   - Compare observable behavior, not just code shape.
   - Include:
     - inputs and schema
     - output columns/fields
     - grouping keys
     - ordering guarantees
     - thresholds and defaults
     - database/query count
     - ownership boundary: current service vs upstream service vs downstream consumer
   - Classify result:
     - `valid`: current implementation differs from PoC or violates expected behavior.
     - `not applicable`: PoC or upstream contract shows comment concern is already handled elsewhere.
     - `unclear`: missing context or ambiguous product decision.

6. **Respond Before Coding**
   - Summarize finding with file/function references.
   - Say whether code change is needed.
   - If implementation is needed, describe the smallest behavior-preserving change and wait for user direction unless they already asked to implement.

7. **When Implementing**
   - Keep edits scoped to the validated gap.
   - Preserve existing service architecture unless PoC parity requires a change.
   - Add focused regression tests for the exact behavior.
   - Do not rewrite unrelated code to resemble the PoC stylistically.
   - Run focused tests and linters when available.

8. **Track PR Answers**
   - If the repo has a PR-comment tracker file, append/update the answer in order.
   - Store:
     - original comment
     - validation result
     - PoC evidence
     - current-service evidence
     - decision
     - suggested PR reply
     - implementation/test status, if changed

## Output Shape

For review-only tasks:

```markdown
Finding: valid | not applicable | unclear

PoC:
- ...

Current service:
- ...

Decision:
- ...

Suggested reply:
...
```

For implementation tasks:

```markdown
Implemented:
- ...

Validated with:
- ...

PR reply:
...
```

## Rules

- Do not implement before validating the PoC and current service.
- Do not assume a PoC function matters just because it exists; verify the entry point uses it.
- Prefer code references and observed data flow over broad claims.
- User clarifications override reviewer assumptions when they describe service boundaries or upstream contracts.
- If the service intentionally delegates behavior to another service, document that boundary instead of duplicating logic.
