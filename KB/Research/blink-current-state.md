---
type: research
date: 2026-09-20
session: 14e4b904
description: What Blink (1Axen/blink) is, its two parallel lines (0.18.9 stable and 1.0.0-pre.10), IDL coverage of each, runtime model, docs, maintenance and install story as of 2026-09-20.
sources: [https://github.com/1Axen/blink, https://1axen.github.io/blink/, https://devforum.roblox.com/t/2959671, "KB/Library/blink-current-state-notes.md"]
tags: [blink, networking, roblox]
---
# Blink: current state as of 2026-09-20 (0.18.9 stable, 1.0.0-pre.10 rewrite)
Up: [[Research]]

**Question:** What is Blink today, what does each line support, and how alive is it?

**Answer:**
- A Luau compiler (run under Lune for 0.18, Lute for 1.0, packaged as a standalone binary) that reads a `.blink` IDL and emits Luau client and server modules, an optional types module and, in 0.18, `.d.ts` files. MIT.
- **Two parallel lines, neither a comfortable target for a new project.** Stable **v0.18.9 (2026-09-19)**, GitHub "Latest", bug-fix only since January 2026 (v0.18.7 Feb, v0.18.8 Apr, v0.18.9 Sept). Rewrite **v1.0.0-pre.10 (2026-09-19)**, tenth pre-release since pre.1 on 2026-01-14; no docs site, syntax learnable only from `examples/*.blink` and release notes; no announced 1.0 date. 91 tags since v0.1.0 (2024-01-05).
- **The syntaxes are incompatible** and there is no migration guide. 0.18: `struct Entity { ... }`, `event Foo { From: Client, Type: Reliable, Call: SingleSync, Data: ... }`, PascalCase options. 1.0: `type entity = struct { ... }`, `event foo = { from: Client, ... }`, snake_case options, everything under `blink.exports.foo.fire(...)`.
- 0.18 IDL: sized ints and floats with ranges (`u8(0..8)`, half-open, exact), `f16`, strings and buffers with length bounds, vectors and CFrames with per-component encodings (`CFrame<i16, f16>`, `vector<u8>`), Instance with class filter, `unknown`, BrickColor, Color3, DateTime, structs with spread-merge (`..`) and generics, unit and tagged enums, maps, sets, arrays, optionals, type packs, scopes, multi-file `import`, `export` types that produce standalone read and write functions, events with five call modes, functions with Coroutine / Future / Promise yield modes, about twelve options (`Casing`, `Typescript`, `TypesOutput`, `WriteValidations` default off, `SyncValidation` default on since 0.18.5, `ManualReplication`, `RemoteScope`).
- 1.0 adds literal types, real unions, recursive types, `u24`, `u48`, an `integer` (int64) type, `StreamedInstance`, Roblox `Enum`, named event parameters, `from: Both` two-way events, compilation profiles (`release` strips write validation, `debug` keeps it), attributes on declarations. It **removes** `f16`, unit `enum`, Promise and Future yield modes, `--watch`, and TypeScript output (the option compiles and emits nothing). No bitpacking (#105 open).
- Runtime: per-destination growable buffer (64 bytes initial, 1.5x growth), flushed through one reliable RemoteEvent and one UnreliableRemoteEvent per scope at the end of every frame (`StepReplication`, callable by hand under `ManualReplication`); per-player server buffers with `Save` / `Load`; unreliable cap 1000 bytes; 256-slot function invocation ring with no timeout; 256-entry queue for events received before a listener attaches. Remotes `BLINK_RELIABLE_REMOTE` / `BLINK_UNRELIABLE_REMOTE` created by the server in ReplicatedStorage.
- Maintenance: one-person project (1Axen, 205 of about 232 contributions; DevForum name Ax3nx). Bursty in 2026 (January to April, silence to late August, a mid-September burst). Fast when active: about twenty issues filed by one tester on 2026-09-15 were mostly closed within one to four days across pre.8 to pre.10. Oldest open issues: #12 plugin freeze (July 2024) and #45 oversized-buffer DoS (May 2025). No formal roadmap.
- Docs: ten to eleven short Starlight pages, accurate for 0.18 but thin (CLI page documents one flag, TypeScript one sentence, nothing on replication or validation internals, no migration guide); newcomers report finding them hard to learn from.
- Install: Rokit (`rokit add 1Axen/blink`), pesde (0.18.5+), GitHub Releases binaries, official Studio plugin on the Creator Store (with a built-in editor that freezes on 150 to 800 line schemas, #12). Community VS Code extension forked from Zap's; unknown whether it targets 1.0 syntax. No Wally or npm package, no web playground, no language server.

**Sources:** GitHub repo, releases API, issues; docs site; DevForum thread; full cited notes in [[Library/blink-current-state-notes]] (2026-09-20).
**Confidence:** high for 0.18 facts and version data (GitHub API); medium for 1.0 semantics, which were read from release notes and examples rather than source, apart from the source snapshot in [[Research/reference-source-snapshots]].
**Applies to:** the coverage matrix, the compiler design (Blink is the primary architectural reference), the bug list, the benchmark re-run.
Related: [[Research/zap-0-6-current-state]] [[Research/blink-0-18-compiler-pipeline]] [[Research/known-bugs-in-zap-and-blink]] [[Research/strengths-to-borrow-from-zap-and-blink]]
