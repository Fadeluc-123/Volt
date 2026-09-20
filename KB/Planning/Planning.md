---
type: path
description: Plans, roadmaps and task breakdowns with their status. Listed at session start; opened on demand.
---
# Planning
Up: [[Core]]

One node per plan. A plan is a goal with ordered steps and a status. Progress is recorded in the plan node itself, so the next session can pick up where the last one stopped.

**Read at session start:** listed only (this index). Open the active plans with Read when the session's work relates to them.

## When to add or update

When the user asks for a plan, when a piece of work is bigger than one turn, or when a roadmap decision is made. Update `status` and the progress notes as work happens; when a plan is finished set `status: done` rather than deleting it.

## Node template

File name: a short kebab-case slug that names the goal, for example `player-movement-v1.md`.

```md
---
type: plan
date: YYYY-MM-DD
session: <first 8 chars of session id>
status: draft
description: <one line: the goal>
tags: []
---
# <Plan title>
Up: [[Planning]]

**Goal:** what done looks like.
**Steps:**
- [ ] step
- [ ] step
**Dependencies and risks:**
**Progress notes:** dated one-liners, newest last.
Related: [[Research/...]] [[Memory/...]]
```

`status` is one of `draft`, `active`, `done`, `dropped`.

## Nodes
<!-- kb:auto-start -->
- [[Planning/volt-benchmark-plan|Volt benchmark plan]] - How to benchmark Blink, Zap and Volt fairly, building on Blink's published harness and adding the scenarios, measurements and fairness controls it lacks.
- [[Planning/volt-next-session-deliverables|Volt: next working session deliverables]] - The ordered deliverables for the next working session on Volt, from the final research pass to name verification, with the research gaps and open questions to close.
<!-- kb:auto-end -->
