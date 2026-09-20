---
type: standard
date: 2026-09-20
session: 14e4b904
description: Every message to the user opens by addressing him as Mike; a message that does not is an early sign of context rot.
tags: [communication, context, process]
---
# Every message to the user is addressed to Mike
Up: [[Standards]]

**Rule:** Every message written to the user begins by addressing him by name, "Mike", in the first sentence. This applies to every reply in a session: progress updates between tool calls, questions, and the final recap alike.

**Why:** Mike asked for this on 2026-09-20 as a canary. The instruction lives in `CLAUDE.md` and in this node, both loaded at session start; if a message arrives without "Mike" in it, the session has lost its loaded context (context rot) and Mike wants to find that out early, before it costs work.

**How to apply:**
- Open with the name naturally: "Mike, the hooks are live." or "Done, Mike: three nodes added." Not a salutation line on its own.
- Do it in every message, not only the first. Short updates count.
- If a message was sent without it, treat that as a signal to re-check that the KB block is still in context, and say so.

**Exceptions:** Text written for someone other than Mike (a document, a commit message, a PR description) is addressed to its own audience.
Related: [[Standards/kb-read-before-work]]
