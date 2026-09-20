---
type: path
description: One node per session with a compact summary of what was done, why and how. Listed at session start; opened on demand.
---
# Memory
Up: [[Core]]

One node per session. A Memory node is the compacted context of a session: what was done, why, how, what the outcome was and what is still open. It is a summary for the next session, not a log of the conversation.

**Read at session start:** listed only (this index). Open the most recent nodes with Read when continuing earlier work.

## When to add or update

The Stop hook prints the exact path for the current session, `KB/Memory/<YYYY-MM-DD>-<first 8 chars of session id>.md`, and refuses to end any turn that changed files, ran non-read-only commands or used web tools until that node has been created or updated with the Write or Edit tool. Later work in the same session updates the same node. Never edit or delete a node from another session.

## Node template

Target under 25 lines. Bullets, not prose. Decisions, not steps.

```md
---
type: memory
date: YYYY-MM-DD
session: <first 8 chars of session id>
description: <one line: what this session was about>
tags: []
---
# <Session title, one line>
Up: [[Memory]]

**What:**
- 2 to 5 bullets of what was done.
**Why:** the goal or request behind it.
**How:** key decisions and approach.
**Outcome:** state at the end; what is verified and what is not.
**Open:** unfinished threads and next steps.
Related: [[Mistakes/...]] [[Research/...]] [[Planning/...]]
```

## Nodes
<!-- kb:auto-start -->
- [[Memory/2026-09-20-14e4b904|Documents bundle and code style ingested into the KB; repo staged]] - Ingested the Documents handoff bundle and Mike's code style into the KB (58 new nodes, two new Paths), set up the repo files, and staged everything for Mike's first commit.
- [[Memory/2026-09-20-997a7da2|KB system and enforcement hooks set up]] - Built the KB vault structure, CLAUDE.md and the hook enforcement; all hooks pipe-tested and live.
<!-- kb:auto-end -->
