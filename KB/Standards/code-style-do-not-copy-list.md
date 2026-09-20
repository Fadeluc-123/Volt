---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 13: shapes that appear in Mike's shipped code but are defects, never reproduced.
tags: [code-style, luau, defects]
---
# Code style §13: the do-not-copy list
Up: [[Standards]]

**Rule:** The shapes below appear in Mike's shipped code but are defects, not conventions. They are never reproduced, and a reviewer sends back a diff that contains one.

**Why:** A style guide derived from real repos would otherwise sanctify their bugs.

**How to apply:** Do not write any of these.

- Component state on the class table instead of per-instance (§8.5).
- `repeat task.wait() until cond` with no timeout as the default async primitive (§6.6.1).
- Conditional React hooks (`if props.animate ~= false then React.useEffect(...)`) (§10.4).
- Client-supplied strings used as unvalidated table indices (`playerData[type][item]`) (§9.3).
- Client-only rate limiting or debounce with no server counterpart (§9.1).
- Rojo path casing that does not match disk (§1.1, §11.1).
- Header comments copy-pasted between files and left describing the wrong system (§2.3).
- Debug `print(value, "value")` left in shipping paths.
- Accidental globals (a module-level `function name()` with no `local`), and `_G` in any form (§6.7).
- A `:Connect`, `task.spawn` loop or subscription with no owner and no disconnect path (§8.6).
- A bare literal passed as an argument instead of a named variable (§5.1).
- A tunable value hardcoded in a service, class or component instead of read from `Config/` (§1.3).
- The same predicate (facing, distance, alive) re-typed per system instead of required from `Shared/Extensions/` (§7.3).
- A yielding predicate; return a Promise instead (§6.6.1).
- `ProximityPrompt` anywhere. All world interaction goes through the custom Interaction system.
- `Humanoid` and default-character assumptions. Character behaviour is written against the custom character controller (default Roblox character runs behind the Character system's API until it lands).
- `error()` followed by unreachable code.
- Declared-but-never-required Wally dependencies (§11.3).
- `game.HttpService` instead of `game:GetService("HttpService")`.
- Annotating a `Vector3` as `: number`, or anything as `: table` (not a Luau type) (§3.3).

**Exceptions:** none.
Related: [[Standards/code-style-overview]] [[Standards/code-style-evolution-notes]] [[Standards/code-style-new-file-checklist]]
