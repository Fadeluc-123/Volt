---
type: research
date: 2026-09-20
session: 14e4b904
description: What each of Zap 0.6, Blink 0.18 and Blink 1.0 does well and Volt should borrow, from Zap's docs and bitpacking to Blink's Blocks builder and same-walk serdes emission.
sources: ["KB/Library/handoff-2026-09-20.md", "KB/Library/zap-vs-blink-report.md"]
tags: [zap, blink, design, requirements]
---
# Strengths to borrow from Zap and Blink
Up: [[Research]]

**Question:** Which ideas from each reference library should Volt carry forward?

**Answer:** Every borrowed item is cited in the design document by source; anything not on this list is new and says why.

### From Zap 0.6
- Documentation structure: nine focused pages, per-option version tags, and an in-browser playground that shows generated output live. Copy the structure.
- TypeScript output that works, with `typescript_enum` and tuple-length options.
- Bitpacking for booleans (v0.6.24 and v0.6.25).
- Ordered unreliable events, `AlignedCFrame`, `FireSet`.
- A documented tooling deserializer for packet inspectors like PacketProfiler.
- Server-side validation always on; `write_checks` only toggles sender-side checks.
- OR types, recursive types, namespaces (v0.6.21), five call modes including Polling, `manual_event_loop`, `include_profile_labels` for microprofiler labels.
- A stable IDL: declared feature complete September 2024, few breaking changes since.

### From Blink 0.18
- A Luau codebase: approachable, patchable, forkable.
- **The `Blocks` builder**: one `Allocate(n)` or `Read(n)` per block with constant offsets, and one allocation for a whole array of fixed-size elements before the loop. This is the core of Blink's CPU edge. Reuse the idea.
- **Read and write code emitted from the same tree walk**, so the two sides cannot disagree on layout.
- Per-player server send buffers with `Save` and `Load`, flushed once per Heartbeat.
- `export` types that generate standalone read and write functions, useful for custom serialization and DataStores.
- Generics, multi-file `import`, scopes, `f16`, per-component `CFrame<i16, f16>` and `vector<u8>` encodings.
- Official Studio plugin, Rokit and pesde install, GitHub binaries.
- A test harness that mocks RemoteEvents through a bridge so generated modules can be unit tested outside Roblox (`test/Shared.luau`, `test/Client.luau`, `test/Server.luau`).

### From Blink 1.0 pre-release
- Compilation profiles: `release` strips write validation, `debug` keeps it.
- Attributes on declarations, literal types, real unions, recursive types, `u24` and `u48`, an `integer` type, `StreamedInstance`, Roblox `Enum` type, named parameters, `from: Both` two-way events, everything under a single `.exports` table.
- No `_G` anywhere in generated output.

**Sources:** [[Library/handoff-2026-09-20]] section 5, drawn from [[Library/zap-vs-blink-report]] and the two current-state notes.
**Confidence:** high that these exist as described; which to adopt is a design choice.
**Applies to:** the design document and the coverage matrix.
Related: [[Research/known-bugs-in-zap-and-blink]] [[Research/networking-use-case-coverage-list]] [[Research/blink-0-18-compiler-pipeline]]
