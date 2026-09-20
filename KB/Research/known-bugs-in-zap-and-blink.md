---
type: research
date: 2026-09-20
session: 14e4b904
description: Every confirmed bug and limitation in Zap 0.6.29, Blink 0.18.9 and Blink 1.0.0-pre.10, with GitHub issue numbers, and what Volt does instead; this list is a requirements list.
sources: [https://github.com/red-blox/zap/issues, https://github.com/1Axen/blink/issues, "KB/Library/handoff-2026-09-20.md"]
tags: [zap, blink, bugs, requirements]
---
# Known bugs and issues in Zap and Blink that Volt fixes
Up: [[Research]]

**Question:** What is broken or missing in the reference libraries, so Volt does not repeat it?

**Answer:** All confirmed 2026-09-20 from GitHub issues and release notes; numbers are issue numbers in the named repo. "Ours" is the intended Volt behaviour, to be confirmed in the design document.

### Shared by both
- **Oversized-buffer denial of service.** Both trust the incoming buffer length and iterate over it server-side. Zap #219 (March 2026) reports real production crashes; Blink #45 (May 2025) is unanswered. Ours: hard cap on incoming buffer length and per-player fire rate limit, both checked before any decode.
- **No documented decode-failure policy.** Blink #102: a nil non-optional Instance drops the rest of the packet silently. Ours: a defined policy per event, drop-packet as default, optional kick hook.
- **Yielding inside a sync callback is undefined behaviour** in both. Ours: detect and error clearly in debug, or make sync listeners impossible to yield from by design.
- **Unreliable payload cap of 1000 bytes** with no fragmentation in either. Ours: reject at compile time when the schema's maximum size exceeds the cap, or document fragmentation as out of scope.
- **`_G` duplicate-instance guard** in Zap 0.6 and Blink 0.18. Ours: none; unique remote scope per generated module ([[Decisions/no-global-state-unique-remote-scope]]).

### Zap 0.6.29
- #216: `Player` memory leak when `Fire` is called after `PlayerRemoving`. Community fix PR #223 closed unmerged 2026-09-12.
- #225: generated modules for large games exceed Roblox bytecode limits because Zap emits one monolithic module per side; a studio maintains a sharding fork. Ours: emit sharded or lazily-required modules above a size threshold.
- #67: no 64-bit integers, open since February 2024; also no 24, 40, 48, 56-bit widths.
- No two-way events, no server-to-client functions, no documented generics; namespaces cannot reference global types.
- v0.6.27 fixed buffer out-of-bounds with 256 or more concurrent function calls: the invocation ring is a fixed 256 slots.
- Maintenance: one release in 2026, rewrite branch dormant since July 2024, unanswered 2026 issues.

### Blink 0.18.9
- #12: Studio plugin editor freezes between roughly 150 and 800 lines of schema, open since July 2024.
- #81: cannot require the client module from Studio edit mode for Storybook-style UI tooling (Zap v0.6.29 supports this).
- `Single*` call modes silently replace a prior listener instead of erroring.
- 256-slot invocation ring for functions with no timeout; the 257th concurrent call errors.
- Tagged enums are not real unions in the emitted Luau types.
- Register exhaustion with many serdes functions (fixed 0.18.7) and NaN bypassing range validation (fixed 0.18.9): classes of bug to test for.
- Docs: eleven short pages, CLI page documents one flag, TypeScript one sentence, no replication or validation internals, no migration guide.
- Two-track syntax: 0.18 syntax will not compile on 1.0.

### Blink 1.0.0-pre.10
- #90: numeric ranges parsed but never enforced (pre.7). #91: a validation error inside `fire()` leaves partial bytes in the outgoing buffer and corrupts the batch. #92: players present before the server module loads break reliable fires. #93: messages received before `on()` silently dropped while the queue grows forever. #94: `vector(range)` crashes at runtime. #98: shipped `examples/generics.blink` fails to compile. #99: options that compile without warnings but do nothing, including `typescript`, `--watch`, `--profile`, `@stable`, `@bitpack`. #105: `@bitpack` not implemented. Most of the September batch was closed in pre.8 to pre.10; the classes remain worth testing.
- No documentation site. Removed versus 0.18: `f16`, unit `enum`, Promise and Future yield modes, `--watch`, TypeScript output.

**Sources:** GitHub issues and releases for both repos; consolidated in [[Library/handoff-2026-09-20]] section 6.
**Confidence:** high; each item was confirmed against the issue or release note on 2026-09-20. Re-check open issues before the design document is finalised.
**Applies to:** [[Decisions/volt-goals]] goal 5; the design document's validation and runtime sections; the benchmark's malformed-packet scenario.
Related: [[Research/zap-0-6-current-state]] [[Research/blink-current-state]] [[Research/networking-use-case-coverage-list]]
