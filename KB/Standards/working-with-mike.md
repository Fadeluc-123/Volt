---
type: standard
date: 2026-09-20
session: 14e4b904
description: What Mike already knows and prefers, so sessions pitch explanations and decisions at the right level.
tags: [communication, user, process]
---
# Working with Mike: what he knows and prefers
Up: [[Standards]]

**Rule:** Sessions assume the knowledge and preferences below and do not re-explain or re-ask them.

**Why:** Learned in the 2026-09-20 research session (see [[Library/session-context-2026-09-20]]). Repeating them wastes Mike's time and signals a session that has not read the KB.

**How to apply:**
- Mike is a Roblox developer at Whiteoak Studio (mike@whiteoak.studio) writing Luau. He understands the Heartbeat-batched buffer networking model, has read Blink's generator source and knows its full pipeline. Explanations can start at that level.
- He does not use `_G` anywhere in runtime code and objects to it in generated output ([[Decisions/no-global-state-unique-remote-scope]]).
- He prefers clear, complete documentation; thin docs were his first reason to lean toward Zap. Documentation written for Volt is complete rather than minimal.
- He leans toward Blink's approach and architecture, and wants to own and maintain his networking layer, customised to his style and workflow.
- He wants Volt lightweight and simple, with a small, regular API so a wrapper that replaces Knit can sit on top of it ([[Decisions/volt-goals]]).
- He reviews and commits every change himself ([[Standards/git-commits-are-manual]]).
- When he writes `Root\...` he means the repository root.
- He once typed "Zip" for Zap; the intended library is Zap.

**Exceptions:** none.
Related: [[Standards/address-mike-in-every-message]] [[Standards/code-style-overview]]
