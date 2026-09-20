---
type: standard
date: 2026-09-20
session: 997a7da2
description: Core, Decisions, Mistakes and Standards are in context before any work starts; hooks enforce it. Research is listed by index and opened on demand.
tags: [kb, process]
---
# The KB is read before any work starts
Up: [[Standards]]

**Rule:** No file is changed, no command is run, no agent is spawned and no web research happens until `KB/Core.md` and every node in `KB/Decisions`, `KB/Mistakes` and `KB/Standards` are in context. `KB/Library`, `KB/Memory`, `KB/Planning` and `KB/Research` are listed by index and opened on demand; the Research index is checked before any new research. (2026-09-20: Decisions added to the required set, Research moved to index-only by Mike to cut the injection size. The list lives in `$RequiredPaths` in `.claude/hooks/kb-common.ps1`.)

**Why:** The KB is the only memory that survives between sessions. Working without it repeats recorded mistakes and redoes recorded research.

**How to apply:**
- Normally the SessionStart hook (`.claude/hooks/kb-session-start.ps1`) injects everything and marks the session as loaded. Look for the "VOLT KNOWLEDGE BASE" block at the top of the context.
- If that block is missing, the PreToolUse hook (`.claude/hooks/kb-pretool.ps1`) denies Write, Edit, shell, Agent and web tools and lists the unread files. Read each one with the Read tool. The PostToolUse hook opens the gate after the last one.
- After a context compaction the SessionStart hook runs again and re-injects the KB.

**Exceptions:** none. Hooks are not disabled to get around this.
