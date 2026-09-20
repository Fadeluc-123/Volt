---
type: research
date: 2026-09-20
session: 14e4b904
description: What Zap (red-blox/zap) is, its version and maintenance state, IDL coverage, output, batching model, docs and install story as of 2026-09-20.
sources: [https://github.com/red-blox/zap, https://zap.redblox.dev, "KB/Library/zap-current-state-notes.md"]
tags: [zap, networking, roblox]
---
# Zap 0.6.x: current state as of 2026-09-20
Up: [[Research]]

**Question:** What is Zap today, what does it support, and how alive is it?

**Answer:**
- A Rust CLI (native binaries plus a WASM build for the playground) that reads a `.zap` IDL and emits Luau client and server modules, an optional shared types file, optional `.d.ts` (`typescript = true`) and a tooling deserializer for packet inspectors. MIT.
- Latest **v0.6.29 (2026-06-23)**, the only 2026 release; 41 tags since v0.1.0 (Dec 2023). Declared "pretty much feature complete" at v0.6.13 (Sept 2024); breaking changes since are rare and small (v0.6.10 remote-path move, v0.6.17 dropped the ID parameter on unreliables, v0.6.24 deprecations that still compile with warnings, v0.6.28 `Reliable` default). The `rewrite` branch is dormant since 2024-07-07: **0.6.x is the product and no next-gen Zap is coming.** A `.zap` schema written today will still compile in a year.
- Maintenance: sasial-dev maintains 0.6.x; the original author is inactive. 2026: five commits (May to June), one release, zero open PRs, nine open issues, two 2026 bug reports without maintainer reply (#216 memory leak, #225 module size), community fix PR #223 closed unmerged 2026-09-12. Historically same-day responses; now thin.
- IDL: `u8`..`u32`, `i8`..`i32`, `f32`, `f64` with inclusive ranges; `string.utf8` / `string.binary` with length bounds; buffers; arrays, maps, sets with size bounds; structs; unit and tagged enums; optionals; OR (union) types since 0.6.20; recursive types; `unknown`; Instance with class constraint, CFrame, `AlignedCFrame`, Vector3, Vector2, `vector(...)`, Color3, BrickColor, DateTime. Events: `from`, `type` Reliable or Unreliable plus **ordered unreliables**, five `call` modes (SingleSync, SingleAsync, ManySync, ManyAsync, Polling), named multi-parameter `data`, `FireSet`. Functions: client to server only, tuple returns, yield / future / promise modes, a fixed 256-slot invocation ring. Namespaces since 0.6.21 (documented only in PR #192). About twenty `opt` settings: outputs, casing, `write_checks`, TypeScript (`typescript_enum`, tuple length), remote naming, `manual_event_loop`, `include_profile_labels`. Missing: 64-bit and 24/40/48/56-bit ints (#67, open since Feb 2024), two-way events, server-to-client functions, documented generics.
- Runtime: per-side outgoing buffer; reliable fires flushed once per Heartbeat through `ZAP_RELIABLE` (RemoteEvent) and `ZAP_UNRELIABLE` (UnreliableRemoteEvent), or via `SendEvents()` under `manual_event_loop`; batch fires serialize once. **Bitpacking for booleans since v0.6.24, fixed in v0.6.25**; resolved types inlined since v0.6.22. Server-side validation always on; `write_checks` toggles sender-side only. v0.6.29 allows requiring the client module from Studio edit mode.
- Docs: nine VitePress pages plus a live Monaco playground showing generated output; per-option version tags. No changelog file, namespaces page, CLI reference or internals write-up.
- Install: Aftman (`aftman add red-blox/zap`) or GitHub Releases binaries; Rokit works but is undocumented. No Wally or npm package. Tooling: web playground, community Studio plugin (Zappy), community VS Code extensions; no official plugin.

**Sources:** GitHub repo, releases API and issues; zap.redblox.dev; full cited notes in [[Library/zap-current-state-notes]] (2026-09-20).
**Confidence:** high. Every fact was checked against the GitHub API and the docs on 2026-09-20.
**Applies to:** the coverage matrix, the strengths-to-borrow list, the bug list, and the benchmark re-run.
Related: [[Research/blink-current-state]] [[Research/known-bugs-in-zap-and-blink]] [[Research/strengths-to-borrow-from-zap-and-blink]] [[Research/reference-source-snapshots]]
