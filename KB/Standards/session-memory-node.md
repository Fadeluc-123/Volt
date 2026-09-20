---
type: standard
date: 2026-09-20
session: 997a7da2
description: Each session writes exactly one short Memory node and updates it, never duplicates it.
tags: [kb, memory, process]
---
# One Memory node per session, short and current
Up: [[Standards]]

**Rule:** Each session has exactly one Memory node at `KB/Memory/<YYYY-MM-DD>-<first 8 chars of session id>.md`. The exact path is printed in the injected session context and in the Stop hook message. It is created the first time the session does work and updated, not duplicated, after later work. Target under 25 lines.

**Why:** Future sessions need to know what was done, why and how without reading a transcript. A log dump buries the useful part.

**How to apply:**
- Sections: What (bullets), Why, How (decisions, not steps), Outcome (what is verified and what is not), Open (next steps). Link any Mistakes, Research or Planning nodes created in the session.
- The Stop hook (`.claude/hooks/kb-stop.ps1`) blocks the end of any turn that changed files, ran non-read-only commands or used web tools until this node is written or updated with the Write or Edit tool. Writing it through a shell command does not count.
- Never edit or delete a Memory node from another session.

**Exceptions:** turns that only read files, only ran read-only commands, or only added KB nodes do not require a Memory update.
