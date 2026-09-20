---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 0: the eight fastest tells that identify code as Mike's, and the eight ratified rules that override every other section.
tags: [code-style, luau]
---
# Code style §0: the sixty-second version and the ratified rules
Up: [[Standards]]

**Rule:** If nothing else is written correctly, these are. Section 0 lists the tells in the order they identify code as Mike's; section 0.1 lists the rules he red-penned himself, which override anything in any other section that contradicts them.

**Why:** These are the fingerprint. A reviewer checks them first and sends a diff back on them.

**How to apply:**

### 0. The sixty-second version

1. `--[[` prose block `--]]` header, then a **blank line**, then `--!strict`, then the services block with **no** blank line after `--!strict`. Four to five lines at eighty columns saying what the file is (§2.1).
2. **Doc comment, blank line, then `function`.** The blank line between `--]]` and `function` is the single strongest fingerprint.
3. `function Service:KnitStart() end` on **one line**, immediately above the real `KnitInit`, always the last thing before `return Service`.
4. `) : ReturnType`, a **space before the return-type colon**; parameter colons stay tight (`player: Player`). StyLua may close this space and its output is accepted (§3.3).
5. **camelCase public methods, `_camelCase` private methods and fields**, next to PascalCase `KnitInit` / `Construct`. This inverts the usual framework convention and is the fastest tell.
6. Backtick interpolation for every string that carries a value, and often when it does not: `` return false, `Locking Conflict` ``.
7. Knit services and controllers are **thin**. All real logic lives in `Modules/Classes/**`.
8. `-- Whiteoak TODO:` for every deferred item.

### 0.1 Ratified rules (2026-07-29; rule 8 added 2026-08-26)

1. **`and`/`or` conditional chains are canonical**: `local holdTime: number = RunService:IsStudio() and 0 or 1.5`. `if/then/else` expressions are legacy. One caveat in §6.5.
2. **No magic arguments.** Anything passed into a call is a named variable first, never a bare literal: `self:teleportPlayer(player, survivorSpawn, spawnDepth)`. Function-scope locals are fine. §5.1.
3. **No `_G`, anywhere in the workspace.** Packages are the only exemption. §6.7.
4. **Anything that yields returns a Promise** instead of blocking; callers `:await()` only when the use case genuinely cannot continue. §6.6.1.
5. **Repeated predicates become shared extensions or classes.** The dot-product facing check is written once in `Shared/Extensions/`, never copy-pasted. §7.3.
6. **Every configurable value lives in a named config file.** Nothing hardcoded, accurate naming, easy to find. §1.3.
7. **Rigorous connection hygiene.** Every connection, loop and callback has an owner and a documented disconnect path. Zero leaks. §8.6.
8. **A comment never records a decision.** No attributions, dates, rulings or history of what the code used to be; no markdown, no shouting. Comments carry constraints; the KB carries the record. Headers are four to five lines at eighty columns saying what the file is. §5.4, §2.1.

**Exceptions:** none.
Related: [[Standards/code-style-overview]] [[Standards/code-style-formatting]] [[Standards/code-style-comments-and-voice]]
