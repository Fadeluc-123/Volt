---
type: library
date: 2026-09-20
session: 14e4b904
title: Zap current state (researcher notes)
origin: Research subagent, deep-research session ee3b949e, 2026-09-20
description: Researcher notes behind the report: nine questions on Zap with takeaways, cited findings, inferences and gaps.
tags: [zap, blink, networking, snapshot]
---
# Zap (red-blox/zap) — Current State as of September 2026
Up: [[Library]]

> Snapshot from 2026-09-20, kept verbatim for citations and detail. Current knowledge: [[Research/zap-0-6-current-state]]. If they disagree with this document, they win.

Research date: 2026-09-20. Zap is a Rust CLI that reads a `.zap` IDL config and generates Luau (and optionally TypeScript definition) networking modules for Roblox. Primary sources: the GitHub repo (`0.6.x` is the default branch), the GitHub REST API, the docs site zap.redblox.dev (built from `docs/` on the `0.6.x` branch), and Blink's benchmark repo.

A note on dates: the human-readable GitHub releases pages (page 2/3) were summarized by the fetch tool with years that contradicted the repo creation date (Dec 14, 2023). All dates below for v0.2.0 onward were therefore taken from the GitHub REST API `published_at` field, which is authoritative.

---

## Key Question 1: Latest released version, release date, and version history (2023 -> Sept 2026)

### Takeaway
The latest release is **v0.6.29, published 2026-06-23**; there have been 41 tagged versions since v0.1.0 (Dec 2023). The release cadence was rapid in 2024 (v0.6.0 -> v0.6.16), steady in H1 2025 (v0.6.17 -> v0.6.25, including the biggest feature drops: OR types, ordered unreliables, namespaces, bitpacking), then slowed to three small releases in H2 2025 and a single one in 2026. No `CHANGELOG.md` exists; GitHub release notes are the changelog.

### Cited Findings

**Latest / totals**
- Latest release is v0.6.29, `published_at` 2026-06-23T07:48:33Z; release assets are `zap-0.6.29-linux-x86_64.zip` (1.28 MB, 9,527 downloads), `zap-0.6.29-macos-aarch64.zip` (258), `zap-0.6.29-macos-x86_64.zip` (9), `zap-0.6.29-windows-x86_64.zip` (679), and `zap-0.6.29-wasm.tgz` (7). Notes: "Allow requiring zap from edit mode (for Storyboards) by @EstebenR in #218" and "Docs: update deprecated Instance and String syntax by @ConfidentLetter in #217" — [GitHub API releases/latest](https://api.github.com/repos/red-blox/zap/releases/latest)
- The tags API lists 41 tags: v0.6.29 down to v0.6.0, then v0.5.1, v0.5.0, v0.4.0, v0.3.3–v0.3.0, v0.2.2–v0.2.0, v0.1.0 — [GitHub API tags](https://api.github.com/repos/red-blox/zap/tags?per_page=100)
- Repo `created_at` is December 14, 2023; `pushed_at` June 23, 2026; default branch `0.6.x`; MIT license; homepage https://zap.redblox.dev — [GitHub API repo](https://api.github.com/repos/red-blox/zap)
- `CHANGELOG.md` returns 404 on both `main` and `0.6.x` (there is no `main` branch; branches are `0.6.x`, `larger-ranges`, `rewrite`) — [raw CHANGELOG main (404)](https://raw.githubusercontent.com/red-blox/zap/main/CHANGELOG.md); [raw CHANGELOG 0.6.x (404)](https://raw.githubusercontent.com/red-blox/zap/0.6.x/CHANGELOG.md); [GitHub API branches](https://api.github.com/repos/red-blox/zap/branches)
- All v0.6.x releases are published by `github-actions[bot]` (CI-driven releases), none flagged prerelease — [GitHub API releases](https://api.github.com/repos/red-blox/zap/releases?per_page=100)

**2026**
- v0.6.29 — 2026-06-23 — allow requiring Zap in Studio edit mode (for Storyboards); docs updated for deprecated `Instance (X)` / `string` syntax — [GitHub API releases p1](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=1); [releases page](https://github.com/red-blox/zap/releases)

**2025**
- v0.6.28 — 2025-12-13 — added `include_profile_labels` (microprofiler labels, PR #212 by nezuo); `Reliable` became the default event `type` (PR #210 by Ezzenix); event-name comments added to generated deserialization code (PR #213); fixed IsServer/IsClient checking order (PR #215) — [GitHub API releases](https://api.github.com/repos/red-blox/zap/releases?per_page=100); [0.6.x commits](https://api.github.com/repos/red-blox/zap/commits?sha=0.6.x&per_page=100)
- v0.6.27 — 2025-10-05 — fixed a rare buffer access out-of-bounds error with 256+ concurrent function calls ("Fix writing garbage packets", PR #209 by daimond113) — [GitHub API releases](https://api.github.com/repos/red-blox/zap/releases?per_page=100); [0.6.x commits](https://api.github.com/repos/red-blox/zap/commits?sha=0.6.x&per_page=100)
- v0.6.26 — 2025-09-28 — validation preventing duplicate Zap instances with identical `remote_scope`/`remote_folder` (PR #208) — [GitHub API releases](https://api.github.com/repos/red-blox/zap/releases?per_page=100)
- v0.6.25 — 2025-07-21 — fixed bitpacking mismatch — [GitHub API releases](https://api.github.com/repos/red-blox/zap/releases?per_page=100)
- v0.6.24 — 2025-07-11 — **deprecated** plain `string` and `Instance (Model)` syntax (replaced by `string.utf8`/`string.binary` and `Instance.Model`, "precise string kinds" PR #203, "path-like class specifiers" PR #204); added TypeScript `const enum` support (PR #202, `typescript_enum` option); implemented **bitpacking** optimization (PR #198); Rust 2024 edition bump — [GitHub API releases](https://api.github.com/repos/red-blox/zap/releases?per_page=100); [0.6.x commits Sep 2024–Jul 2025](https://api.github.com/repos/red-blox/zap/commits?sha=0.6.x&since=2024-09-01T00:00:00Z&until=2025-07-20T00:00:00Z&per_page=100)
- v0.6.23 — 2025-06-25 — fixed regression preventing builtin types in namespaces (PR #199) — [GitHub API releases](https://api.github.com/repos/red-blox/zap/releases?per_page=100)
- v0.6.22 — 2025-06-24 — inlined resolved types ("Remove Ty::Ref where possible", PR #197); fixed nested type resolution; relaxed set type constraints — [GitHub API releases](https://api.github.com/repos/red-blox/zap/releases?per_page=100)
- v0.6.21 — 2025-06-22 — **Namespaces** (PR #192 by daimond113); fixed regression in recursive type support (#188); fixed TypeScript iteration (#195); loosened restrictions on set & list types (#191); fixed inaccurate variants value (#187) — [v0.6.21 release](https://github.com/red-blox/zap/releases/tag/v0.6.21)
- v0.6.20 — 2025-04-13 — **OR (union) type syntax**; **ordered unreliables** (PR #182); fixed unreliable polling; generated modules always return a value; fixed buffer length validation with `write_checks`; optimizations (NumTy offset calc, table-like length storage, map/set size calc, unit enum size calc); docs migrated to Bun. Contributors: AzzaDeveloper, sasial-dev, daimond113, Ketasaja — [v0.6.20 release](https://github.com/red-blox/zap/releases/tag/v0.6.20)
- v0.6.19 — 2025-03-08 — fixed tagged variant index serialization, tooling deserializer issues, TypeScript type emission; quoted identifiers containing spaces; optimized length storage — [GitHub API releases p3](https://api.github.com/repos/red-blox/zap/releases?per_page=5&page=3); [releases page 2](https://github.com/red-blox/zap/releases?page=2)
- v0.6.18 — 2025-02-20 — added `Polling` call type and `types_output` option; increased max unreliable message size (per Roblox release #656); disallowed f64 vector components; fixed promise/future mocking in function calls — [GitHub API releases p3](https://api.github.com/repos/red-blox/zap/releases?per_page=5&page=3); [releases page 2](https://github.com/red-blox/zap/releases?page=2)
- v0.6.17 — 2025-01-26 — "major release": `vector` type, event ID optimization (IDs split by server/client and reliable/unreliable), actor support for remote functions, initial test suite; releases page summary flags a **breaking change** that unreliable events no longer pass ID parameters — [GitHub API releases p3](https://api.github.com/repos/red-blox/zap/releases?per_page=5&page=3); [releases page 2](https://github.com/red-blox/zap/releases?page=2)

**2024**
- v0.6.16 — 2024-12-13 — fixed rare event-ID serialization bug when total events+functions > 256 — [GitHub API releases p3](https://api.github.com/repos/red-blox/zap/releases?per_page=5&page=3)
- v0.6.15 — 2024-12-02 — `| undefined` added to TS emit for optionals; multiple named parameters for `data`/`args`/`rets` — [GitHub API releases p3](https://api.github.com/repos/red-blox/zap/releases?per_page=5&page=3)
- v0.6.14 — 2024-09-22 — CFrameSpecialCases in tooling output; `disable_fire_all` option — [GitHub API releases p2](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=2)
- v0.6.13 — 2024-09-09 — `--no-warnings` CLI arg; release notes state "Zap `0.6.x` is pretty much feature complete at this point." — [v0.6.13 release](https://github.com/red-blox/zap/releases/tag/v0.6.13)
- v0.6.12 — 2024-08-14 — fixed sync-function regression from v0.6.10 — [GitHub API releases p2](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=2)
- v0.6.11 — 2024-08-13 — fixed `remote_folder` not applied to tooling — [GitHub API releases p2](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=2)
- v0.6.10 — 2024-08-13 — **breaking**: default remote path moved to `ReplicatedStorage/ZAP`; `remote_folder` option; generalized tooling; Luau function return type annotations — [releases page 2](https://github.com/red-blox/zap/releases?page=2); [GitHub API releases p2](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=2)
- v0.6.9 — 2024-07-20 — `set` type; boolean literals in tagged enums; tydecl refactor — [GitHub API releases p2](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=2)
- v0.6.8 — 2024-07-01 — fixed length checks and enum sizing; TS output auto-detects Promise libraries — [GitHub API releases p2](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=2)
- v0.6.7 — 2024-06-29 — `remote_scope` option; TS uses `Map<K,V>`; shadowing fixes — [GitHub API releases p2](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=2)
- v0.6.6 — 2024-06-25 — `FireSet`; `DateTime`, `BrickColor`, `Vector2` types; TS improvements — [GitHub API releases p2](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=2)
- v0.6.5 — 2024-06-24 — hotfix for `RunService:IsEdit()` security constraint (v0.6.4 same day, marked "use v0.6.5 instead") — [GitHub API releases p2](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=2); [GitHub API releases p6](https://api.github.com/repos/red-blox/zap/releases?per_page=5&page=6)
- v0.6.3 — 2024-03-14 — event queue no longer errors at capacity for dataless events — [GitHub API releases p6](https://api.github.com/repos/red-blox/zap/releases?per_page=5&page=6)
- v0.6.2 — 2024-03-09 — `On` returns a disconnect function; nested struct/array shadowing fixes — [GitHub API releases p6](https://api.github.com/repos/red-blox/zap/releases?per_page=5&page=6)
- v0.6.1 — 2024-01-09 — fixed optional-data event queue callbacks — [GitHub API releases p6](https://api.github.com/repos/red-blox/zap/releases?per_page=5&page=6)
- v0.6.0 — 2024-01-09 — **breaking**: exit code 1 on error diagnostics; added remote functions, optional `data`/`args`/`rets`, `manual_event_loop`, CFrame axis-angle compression — [GitHub API releases p6](https://api.github.com/repos/red-blox/zap/releases?per_page=5&page=6); [releases page 3](https://github.com/red-blox/zap/releases?page=3)
- v0.5.1 — 2024-01-02 — fixed unreliable remote instance handling — [GitHub API releases p3 (per_page=15)](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=3)
- v0.5.0 — 2024-01-01 — `CFrame` and `Color3` types; prevented duplicate remotes — [same](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=3)

**2023**
- v0.4.0 — 2023-12-31 — event queueing; `unknown` type — [same](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=3)
- v0.3.3 — 2023-12-30; v0.3.2 — 2023-12-30; v0.3.1 — 2023-12-30 (TypeScript support, parser rewrite); v0.3.0 — 2023-12-30 (**major breaking**: type renames, keyword syntax changes, `buffer` support) — [same](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=3)
- v0.2.2 — 2023-12-19; v0.2.1 — 2023-12-18 (separate output files); v0.2.0 — 2023-12-17 — [same](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=3)
- v0.1.x — earlier than 2023-12-17 (repo created 2023-12-14) — [GitHub API repo](https://api.github.com/repos/red-blox/zap)

### Inferences
- Release cadence by year: ~15 releases Dec 2023–Dec 2024, 12 releases in 2025, 1 release in 2026 (through Sept 20). Activity has clearly tapered in 2026.
- Breaking changes have been rare and small since v0.6.0 (v0.6.10 remote path; v0.6.17 unreliable ID param; v0.6.24 deprecations that still compile with warnings). The project has stayed on 0.6.x for 2.7 years.

### Gaps
- Exact dates for v0.1.0–v0.1.3 were not captured (API summary said "earlier"; tags list shows only v0.1.0, releases summary listed v0.1.1–v0.1.3 — minor inconsistency, unresolved).
- The v0.6.17 "breaking change" wording came from the releases HTML summary, not verbatim release notes; treat the specific phrasing as approximate.

---

## Key Question 2: What the Zap config/IDL language supports

### Takeaway
Zap's IDL covers fixed-width integers/floats with inclusive range constraints, constrained strings (`string.utf8`/`string.binary`), buffers, arrays, maps, sets, structs, unit and tagged enums, optionals, union (OR) types, `unknown`, and Roblox types (Instance with class, CFrame, AlignedCFrame, Vector3/Vector2/`vector(...)`, Color3, BrickColor, DateTime); events support `from`, `type` (Reliable/Unreliable, ordered unreliables), five `call` modes, named multi-parameter `data`; functions are client->server->client only with tuple returns and yield/future/promise modes; namespaces exist since v0.6.21; ~20 top-level `opt` settings control outputs, casing, checks, TypeScript, remote naming and the event loop.

### Cited Findings

**Types** (docs: [Types page](https://zap.redblox.dev/config/types); [raw types.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/config/types.md))
- Numbers: `i8`, `i16`, `i32`, `u8`, `u16`, `u32`, `f32`, `f64`; constraint syntax `u8(0..100)` — [Types](https://zap.redblox.dev/config/types)
- Range syntax is inclusive two-dot: `0..100`, `0..`, `..100`, exact `0`, unbounded `..` — [Types](https://zap.redblox.dev/config/types)
- Strings: `string.utf8(3..20)`, `string.binary(0..50)` with optional length ranges; plain `string` and `Instance (Model)` syntax deprecated in v0.6.24 — [Types](https://zap.redblox.dev/config/types); [GitHub API releases](https://api.github.com/repos/red-blox/zap/releases?per_page=100)
- Arrays: `u8[10..20]`; Maps: `map { [string]: u8 }`; Sets: `set { string }` ("equivalent to map with boolean values") — [Types](https://zap.redblox.dev/config/types)
- Structs: `struct { name: string, price: u32 }`; Unit enums: `enum { "Starting", "Playing", "Intermission" }`; Tagged enums: `enum "type" { "number": { value: number }, "string": { value: string } }` — [Types](https://zap.redblox.dev/config/types)
- Instances: `Instance` or `Instance.BasePart` (dot notation); "Classes that inherit your specified class will be accepted"; a non-optional Instance that resolves to `nil` on receive is a deserialize error, so use `Instance.Player?` for possibly-nonexistent instances — [raw types.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/config/types.md)
- `CFrame` compressed via axis-angle rotation and "orthonormalized when sent"; `AlignedCFrame` stores axis-aligned rotation as a single byte enum — [raw types.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/config/types.md)
- Vectors [0.6.17+]: `vector(f32, f32, f32)` with any numeric component type except `f64`, Z optional (defaults to 0); also `Vector3`, `Vector2` — [raw types.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/config/types.md)
- `DateTime`, `DateTimeMillis`, `Color3`, `BrickColor` — [Types](https://zap.redblox.dev/config/types)
- `unknown` ("data of a type that can't be known until runtime"; docs recommend tagged enums when the set of types is known) — [raw types.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/config/types.md)
- Optionals: append `?` to the whole type — [raw types.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/config/types.md)
- OR/union types [0.6.20+]: `"hello" | "world" | number | Instance`; resolved by runtime type check in order; "you cannot have both `u8` and `u16`"; a union containing `unknown` is implicitly optional; optionals cannot be nested inside unions — [raw types.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/config/types.md)
- `buffer` support added in v0.3.0 — [GitHub API releases p3](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=3)
- Bitpacking of booleans/small fields was added in v0.6.24 (PR #198) — [0.6.x commits](https://api.github.com/repos/red-blox/zap/commits?sha=0.6.x&since=2024-09-01T00:00:00Z&until=2025-07-20T00:00:00Z&per_page=100)

**Events** ([Events page](https://zap.redblox.dev/config/events))
- Declared with `event Name = { from, type, call, data }`; `from`: `Server` or `Client`; "Zap does not support two way events" (declare two events) — [Events](https://zap.redblox.dev/config/events)
- `type`: `Reliable` ("guaranteed to arrive at their destination in the order they were sent") or `Unreliable` (no arrival/order guarantee, 1000-byte max); `Reliable` is the default since v0.6.28 — [Events](https://zap.redblox.dev/config/events); [GitHub API releases](https://api.github.com/repos/red-blox/zap/releases?per_page=100)
- Ordered unreliables added in v0.6.20 (PR #182 "Add ordered unreliables") — [v0.6.20 release](https://github.com/red-blox/zap/releases/tag/v0.6.20); [closed PRs](https://github.com/red-blox/zap/pulls?q=is%3Apr+is%3Aclosed+sort%3Aupdated-desc)
- `call`: `ManyAsync`, `ManySync`, `SingleAsync`, `SingleSync`, `Polling` [0.6.18+, iterate via `event.iter()`]; sync warning: yielding causes "undefined and game-breaking behavior" and errors cause "the packet to be dropped" — [Events](https://zap.redblox.dev/config/events)
- `data`: any Zap type; optional; named multi-parameter form `data: (Foo: u32, Bar: string)`; parentheses/names optional for backward compat (single unnamed param) — [Events](https://zap.redblox.dev/config/events); [Getting Started](https://zap.redblox.dev/intro/getting-started)

**Functions** ([Functions page](https://zap.redblox.dev/config/functions))
- Keyword `funct`; fields `call` (`Async` | `Sync`), `args`, `rets`; `rets` cannot be named; tuple returns via `(type1, type2)` — [Functions](https://zap.redblox.dev/config/functions)
- "Zap only supports Client -> Server -> Client functions, not Server -> Client -> Server" — [Functions](https://zap.redblox.dev/config/functions)
- Actor support for remote functions added in v0.6.17 — [GitHub API releases p3](https://api.github.com/repos/red-blox/zap/releases?per_page=5&page=3)

**Namespaces** ([PR #192](https://github.com/red-blox/zap/pull/192))
- Syntax: `namespace my_namespace = { type SomeType = u8  event OneUnnamedParameter = { from: Client, type: Reliable, call: ManyAsync, data: SomeType } }` and `type ThatType = my_namespace.SomeType`; events/functions are "wrapped within a table using the namespace name as the key"; merged 2025-06-22, approved by sasial-dev and jackhexed — [PR #192](https://github.com/red-blox/zap/pull/192)
- Open bug #211 (Oct 26, 2025): "Namespaces can't access global types" — [Issues](https://github.com/red-blox/zap/issues)

**Options** ([Options page](https://zap.redblox.dev/config/options); [raw options.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/config/options.md))
- `server_output`, `client_output` (file paths), `types_output` [0.6.18+], `call_default` [0.6.18+], `remote_scope` (default `"ZAP"` -> remotes `ZAP_RELIABLE`/`ZAP_UNRELIABLE`), `remote_folder` (default `"ZAP"` under ReplicatedStorage), `casing` (`PascalCase` default | `camelCase` | `snake_case`; affects API function names only), `write_checks` (default `true`; "Zap only checks types that can't be statically verified by Luau/TypeScript"), `typescript` (default `false`), `typescript_max_tuple_length` (default 10), `typescript_enum` (`StringLiteral` default | `ConstEnum` | `StringConstEnum`, 0.6.24+), `manual_event_loop` (default `false`), `include_profile_labels` (default `false`), `yield_type` (`yield` default | `future` | `promise`), `async_lib` (require string, required for future/promise), `tooling` (default `false`), `tooling_output` (default `"Zap/tooling.lua"`), `tooling_show_internal_data` (default `false`), `disable_fire_all` (default `false`) — [Options](https://zap.redblox.dev/config/options)

### Inferences
- The type system is broad enough for typical game state but has no 64-bit ints or 24/40/48/56-bit ints (open feature request #67 since Feb 2024), and no generic/parametric types were found in the docs.
- Because `write_checks` defaults to true and validation of received data is always on, Zap validates on both ends by default; turning off `write_checks` is a production optimization.

### Gaps
- I did not find a documented CLI flag list beyond `--no-warnings` (no watch mode found in docs).
- Whether `Instance` keys in maps are supported was only asserted in marketing copy ("Maps with Instance keys") on the What-is-Zap page, not in the Types reference I could see.

---

## Key Question 3: Output targets and tooling (Luau, TypeScript, CLI, plugin, VS Code, playground)

### Takeaway
Zap outputs Luau server and client modules (plus optional shared Luau types file and a tooling deserializer), and can emit TypeScript `.d.ts` definitions alongside for roblox-ts via `typescript = true`. Tooling is a native CLI (Linux/macOS/Windows binaries, plus a WASM build) and an in-browser playground; there is no official Studio plugin, official VS Code extension, or npm package — two community VS Code extensions exist.

### Cited Findings
- Running `zap path/to/config.zap` generates two Luau files at `server_output`/`client_output`; by default outputs go to a `network` folder — [Getting Started](https://zap.redblox.dev/intro/getting-started); [raw generation.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/usage/generation.md)
- `typescript = true` "generate[s] TypeScript definition files alongside generated Luau code"; TypeScript support first arrived in v0.3.1 (Dec 30, 2023) — [Options](https://zap.redblox.dev/config/options); [GitHub API releases p3](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=3)
- `types_output` writes Luau type definitions to a separate file (v0.6.18+) — [Options](https://zap.redblox.dev/config/options)
- Tooling output: a Lua deserializer accepting "The remote instance itself (`RemoteEvent | UnreliableRemoteEvent`)" plus all remote args, returning `{ Name, Arguments }` objects (plus `EventId`/`CallId` when `tooling_show_internal_data`); intended for PacketProfiler-style inspectors; "It is not intended behavior for you to run side effects if you deserialise the data yourself" — [raw tooling.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/usage/tooling.md)
- Release binaries: linux-x86_64, macos-aarch64, macos-x86_64, windows-x86_64 zips, and a `wasm.tgz` — [GitHub API releases/latest](https://api.github.com/repos/red-blox/zap/releases/latest)
- Playground: the docs' `playground.md` is a Vue 3 page using Monaco editor that imports `run` from `../zap/package` and re-compiles on edit, with output tabs for Client (Lua + TS defs), Server (Lua + TS defs), Tooling, and Types; supports shareable base64 URLs — [raw playground.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/playground.md); nav link at [Playground](https://zap.redblox.dev/playground)
- The Generate Code page says users can alternatively paste config into the playground and copy generated code out — [raw generation.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/usage/generation.md)
- Community VS Code extensions: `tijnepema/zap-vscode` ("Syntax highlighting and intellisense for the Zap IDL", based on the playground) and `Naxious/zap_nax` — [zap-vscode](https://github.com/tijnepema/zap-vscode); [zap_nax](https://github.com/Naxious/zap_nax)
- Issue #11 "[FEAT] Zap LSP" (opened by sasial-dev) was closed 2025-06-23 — [closed issues](https://github.com/red-blox/zap/issues?q=is%3Aissue+is%3Aclosed+sort%3Aupdated-desc)
- `@rbxts/zap` does not exist on npm (registry returns 404) — [npm registry](https://registry.npmjs.org/@rbxts/zap)
- Generated code can now be required from Studio edit mode (v0.6.29, "for Storyboards") — [GitHub API releases/latest](https://api.github.com/repos/red-blox/zap/releases/latest)

### Inferences
- roblox-ts users run the native CLI (via Rokit/Aftman or a release binary) with `typescript = true`; there is no npm-distributed CLI or types package.
- The WASM build exists to power the playground and could support other JS tooling, but no official VS Code/Studio integration ships from red-blox.

### Gaps
- Why issue #11 (Zap LSP) was closed (implemented, declined, or superseded) was not determined.

---

## Key Question 4: How Zap batches and sends packets; performance characteristics

### Takeaway
Zap serializes each fire into a per-side outgoing buffer and flushes reliable events/functions once per `RunService.Heartbeat` through a single `ZAP_RELIABLE` RemoteEvent (and `ZAP_UNRELIABLE` UnreliableRemoteEvent), or on demand via `SendEvents()` when `manual_event_loop = true`; batch fires serialize once. Blink's own benchmarks (the only third-party numbers found) show Zap within ~0.2–1% of Blink on bandwidth but 10–50% lower frame rate under heavy send loads.

### Cited Findings
- `manual_event_loop`: "This option determines if Zap automatically sends reliable events and functions each Heartbeat. When enabled, the `SendEvents` function exported from the client and server modules that must be called manually." The docs warn Roblox has issues firing remotes above 60 Hz, and that Zap uses `RunService.Heartbeat` (61 Hz) by default — [raw options.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/config/options.md)
- `remote_scope` default `"ZAP"` yields two remotes, `ZAP_RELIABLE` and `ZAP_UNRELIABLE`, placed in the `remote_folder` under ReplicatedStorage — [raw options.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/config/options.md)
- Event queueing was introduced in v0.4.0 (Dec 31, 2023); event IDs were split by server/client and reliable/unreliable in v0.6.17 to shrink headers — [GitHub API releases p3](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=3); [GitHub API releases p3 (per_page=5)](https://api.github.com/repos/red-blox/zap/releases?per_page=5&page=3)
- "Batch server functions (`FireAll`, `FireExcept`, `FireList`, `FireSet`) serialize data once, making them more efficient than individual fires" — [Generated API](https://zap.redblox.dev/usage/generated-api)
- Unreliable events are limited to 1000 bytes — [Events](https://zap.redblox.dev/config/events)
- Marketing claims: data is "packed all data into buffers, which on top of using less space for the same data, also compress when passed through RemoteEvents"; generated code is "specific to your game" with "minimal branching and minimal calls"; "Zap's packing and unpacking is typically faster than Roblox's generic encoding" — [What is Zap](https://zap.redblox.dev/intro/what-is-zap); [raw README](https://raw.githubusercontent.com/red-blox/zap/0.6.x/README.md)
- `include_profile_labels` (v0.6.28) adds microprofiler labels for diagnosing per-event cost — [Options](https://zap.redblox.dev/config/options)
- Blink benchmark (updated Apr 30, 2025; blink v0.17.1, zap v0.6.20, bytenet v0.4.3; 1000 fires/frame for 10 s on a Ryzen 9 7900X): Entities — median FPS Blink 42, Zap 39, ByteNet 32, Roblox 16; bandwidth Kbps Blink 41.81, Zap 41.71, ByteNet 41.64, Roblox 559,364. Booleans — FPS Blink 97, Zap 52, ByteNet 35, Roblox 21; Kbps Blink 7.91, Zap 8.10, ByteNet 8.11. 0% packet loss all libraries — [Blink Benchmarks.md](https://github.com/1Axen/blink/blob/main/benchmark/Benchmarks.md)
- Earlier revision of the same file (test date May 6, 2024; blink v0.11.1, zap v0.6.3, bytenet v0.4.3): Entities FPS Blink 25, ByteNet 22, Zap 21, Roblox 15; Kbps Blink 41.61, Zap 42.17, ByteNet 41.76. Booleans FPS Blink 60, Zap 34, ByteNet 21, Roblox 16; Kbps Blink 8.48, Zap 8.68, ByteNet 8.97 — [Blink Benchmarks.md @720048b](https://raw.githubusercontent.com/1Axen/blink/720048b/benchmark/Benchmarks.md)
- Zap's own bitpacking (v0.6.24, after the last Blink benchmark) was added to reduce boolean/small-field size — [0.6.x commits](https://api.github.com/repos/red-blox/zap/commits?sha=0.6.x&since=2024-09-01T00:00:00Z&until=2025-07-20T00:00:00Z&per_page=100)
- Open enhancement #219 (Mar 25, 2026): "Allow Zap to Mediate Throughput to Stop Roblox Servers being Unable To Process All Events" — [Issues](https://github.com/red-blox/zap/issues)

### Inferences
- The Blink numbers are produced by a competitor's author; they are the only published head-to-head figures found and have not been re-run against Zap >= v0.6.24 (bitpacking) so the boolean-bandwidth gap may have narrowed.
- Zap publishes no benchmarks of its own; performance claims on the docs site are qualitative.

### Gaps
- No official Zap-authored benchmark or performance documentation was found.
- Exact internal buffer growth strategy (a "resize factor of 1.5" commit exists on the shared history, Jan 29, 2024) was not documented on the docs site — [rewrite-branch commits](https://api.github.com/repos/red-blox/zap/commits?sha=rewrite&per_page=100)

---

## Key Question 5: Documentation quality and coverage (zap.redblox.dev)

### Takeaway
The docs site is a small VitePress site with nine content pages (Intro x2, Config x4, Usage x3) plus a live playground; it has a complete options and types reference and short getting-started/API pages, but it lacks a changelog, a namespaces page, a migration guide, CLI flag reference, or any performance/architecture writeup, and it explicitly covers only 0.6.x.

### Cited Findings
- Sidebar: Introduction (What is Zap?, Getting Started); Configuring Zap (Options, Types, Events, Functions); Using Zap (Generate Code, Event and Function API, Tooling Integration); top nav: Home, Playground — [raw .vitepress/config.mts](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/.vitepress/config.mts)
- README: "Full documentation can be found at zap.redblox.dev (for version 0.6.x)" — [raw README](https://raw.githubusercontent.com/red-blox/zap/0.6.x/README.md)
- The Options page is a full reference table with defaults and version tags (e.g., `types_output` 0.6.18+, `typescript_enum` 0.6.24+) — [Options](https://zap.redblox.dev/config/options)
- The Types page documents every type with syntax and version tags (e.g., OR types 0.6.20+, vectors 0.6.17+) — [raw types.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/config/types.md)
- Getting Started shows a minimal config and `Zap.MyEvent.FireAll(123, "hello world")` / `Zap.MyEvent.On(function(Foo, Bar) ... end)` usage — [Getting Started](https://zap.redblox.dev/intro/getting-started)
- The Generated API page documents `Fire`, `FireAll`, `FireExcept`, `FireList`, `FireSet`, `SetCallback`, `On` (returns Disconnect), `Call`, and the sync-callback caveats, but does not cover `SendEvents`, namespaces, or Heartbeat mechanics — [Generated API](https://zap.redblox.dev/usage/generated-api)
- Docs were updated for deprecated Instance/string syntax in Feb 2026 (PR #217) — [closed PRs](https://github.com/red-blox/zap/pulls?q=is%3Apr+is%3Aclosed+sort%3Aupdated-desc)
- The docs build was migrated to Bun in v0.6.20 — [v0.6.20 release](https://github.com/red-blox/zap/releases/tag/v0.6.20)
- Namespaces are documented only in PR #192, not on a docs page (not in sidebar) — [PR #192](https://github.com/red-blox/zap/pull/192); [config.mts](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/.vitepress/config.mts)

### Inferences
- Documentation is accurate and current for 0.6.x but thin; a newcomer will rely on the playground and release notes for features added after mid-2025 (namespaces, bitpacking, profile labels).

### Gaps
- I could not render the playground's runtime to confirm the default example it ships with.

---

## Key Question 6: Maintenance health (maintainers, commit frequency 2025–2026, issues, responsiveness, roadmap/v1)

### Takeaway
Zap is in low-activity maintenance mode: the `0.6.x` branch is maintained by sasial-dev with contributions mostly from daimond113, nezuo and Ketasaja; the original author jackdotink/jackhexed's `rewrite` branch has had no commits since July 7, 2024. 2026 has seen 5 commits (all May–June), one release, zero open PRs, 9 open issues (two 2026 bug reports with no maintainer reply visible), and no published roadmap or v1 target.

### Cited Findings
- README: "Zap is currently undergoing a rewrite, which can be found at the rewrite branch" and "versions 0.6.x are being maintained by @sasial-dev, on the 0.6.x branch"; contributions should be discussed via issues or "the Roblox Open Source Software Community Discord" — [raw README](https://raw.githubusercontent.com/red-blox/zap/0.6.x/README.md)
- Rewrite branch README: "Zap is currently in a early pre-release state. The API may change over time and there are likely bugs." No version target or roadmap — [rewrite README](https://github.com/red-blox/zap/blob/rewrite/README.md)
- Rewrite branch commit history: "initial rewrite commit" 2024-02-29, "rewrite rewrite lol" 2024-04-06, "rewrite rewrite rewrite" 2024-06-10, last commit "make CI run for all PRs" 2024-07-07 by Jack; 11 of the branch-specific commits by jackdotink — [rewrite commits](https://api.github.com/repos/red-blox/zap/commits?sha=rewrite&per_page=100)
- Contributors (all-time commits): sasial-dev 133, jackhexed 98, Ketasaja 31, daimond113 26, nezuo 13, dependabot 9, gaymeowing 6, then ~13 one- or two-commit contributors — [GitHub API contributors](https://api.github.com/repos/red-blox/zap/contributors?per_page=30)
- `0.6.x` commits by month: 2025-06: 17, 2025-07: ~5, 2025-09: 3, 2025-10: 2, 2025-11: 1, 2025-12: 7, 2026-01 to 2026-04: 0, 2026-05: 4 (one feature PR + three dependabot bumps), 2026-06: 1 (version bump), 2026-07 to 2026-09-20: 0 — [0.6.x commits](https://api.github.com/repos/red-blox/zap/commits?sha=0.6.x&per_page=100); [0.6.x commits Sep 2024–Jul 2025](https://api.github.com/repos/red-blox/zap/commits?sha=0.6.x&since=2024-09-01T00:00:00Z&until=2025-07-20T00:00:00Z&per_page=100)
- Repo stats: 187 stars, 29 forks, 7 watchers, 9 open issues, `pushed_at` 2026-06-23 — [GitHub API repo](https://api.github.com/repos/red-blox/zap)
- Issue counts: 47 closed issues; 166 total PRs, 0 open — [search: closed issues](https://api.github.com/search/issues?q=repo:red-blox/zap+is:issue+is:closed); [search: PRs](https://api.github.com/search/issues?q=repo:red-blox/zap+is:pr); [closed PRs](https://github.com/red-blox/zap/pulls?q=is%3Apr+is%3Aclosed+sort%3Aupdated-desc)
- Open issues (Sept 2026): #225 sharding bug (Sep 10, 2026), #224 Studio-only Promise stub bug (Jul 14, 2026), #219 throughput mediation (Mar 25, 2026), #216 Player memory leak after PlayerRemoving (Jan 8, 2026), #211 namespaces can't access global types (Oct 26, 2025), #196 auto-generated types (Jun 11, 2025), #190 check if event connected (Apr 17, 2025), #72 Channels (Feb 17, 2024), #67 24/40/48/56/64-bit ints (Feb 8, 2024) — [Issues](https://github.com/red-blox/zap/issues)
- Issue #216 (memory leak) shows no maintainer reply in the visible thread; PR #223 "Dont send after PlayerRemoving" by Ezzenix (opened 2026-05-02) was closed unmerged on 2026-09-12 — [Issue #216](https://github.com/red-blox/zap/issues/216); [search: PRs](https://api.github.com/search/issues?q=repo:red-blox/zap+is:pr)
- Issue #225 (Sep 10, 2026) has no maintainer response in the visible thread — [Issue #225](https://github.com/red-blox/zap/issues/225)
- Historical responsiveness was fast: e.g., #189 Encryption closed next day (2025-04-17), #177 closed in 4 days (2025-03-24), #133 closed in 2 days (2024-09-13), #130 closed in 2 days (2024-08-13), #115 and #112 closed same day (2024) — [search: closed issues](https://api.github.com/search/issues?q=repo:red-blox/zap+is:issue+is:closed)
- PR #218 (feature, opened 2026-03-15) was merged 2026-05-02, ~7 weeks later; PR #215 merged in 4 days (Dec 2025); PRs #212/#213 merged within 1–4 days (Nov/Dec 2025) — [search: PRs](https://api.github.com/search/issues?q=repo:red-blox/zap+is:pr)
- v0.6.13 (Sep 2024) release notes: "Zap `0.6.x` is pretty much feature complete at this point." — [v0.6.13 release](https://github.com/red-blox/zap/releases/tag/v0.6.13)
- Dependabot is active (three dependency bumps merged May 2026) — [0.6.x commits](https://api.github.com/repos/red-blox/zap/commits?sha=0.6.x&per_page=100)

### Inferences
- "jackhexed" (98 commits) and "jackdotink" (rewrite-branch author) appear to be the same person under a renamed GitHub handle; jackhexed still reviewed/approved PR #192 in June 2025, so the original author remains involved in review but not in shipping the rewrite.
- The rewrite has been dormant for 26 months; a new project should plan on 0.6.x as the long-term API, with no v1 in sight.
- Bug-fix responsiveness degraded in 2026: two bug reports (Jan and Sep 2026) sit without visible replies and a community fix PR was closed rather than merged.

### Gaps
- Commit counts for Sep 2024–May 2025 on `0.6.x` were not reliably captured by the fetch summary (releases confirm activity in that window).
- The reason PR #223 was closed unmerged was not visible.
- No DevForum announcement thread for Zap was found in three searches; the project appears to be promoted through the Roblox OSS Discord and GitHub rather than the DevForum.

---

## Key Question 7: Known limitations, complaints, and footguns

### Takeaway
The most consequential reported limitation is that large projects hit Roblox bytecode/compile limits because Zap emits one monolithic module per side (issue #225, which forced a studio to fork). Other footguns: sync callbacks that yield cause undefined behavior and errors drop packets; no two-way events; functions are client->server only; unreliable payloads capped at 1000 bytes; a Player memory leak when firing after PlayerRemoving; namespaces can't reference global types; no 64-bit ints; and several deprecated-syntax changes across 0.6.x.

### Cited Findings
- #225 (Sep 10, 2026, InfiniteYield): "after you get enough Zap events, just due to regular complexity, the generated modules are so big they can't even get past bytecode generation"; proposes `opt max_events_per_file = int`; the reporter's studio forked Zap to add sharding — [Issue #225](https://github.com/red-blox/zap/issues/225)
- #216 (Jan 8, 2026): "After the `PlayerRemoving` event fires for a player, if any calls are made to `Fire` or another dispatcher, zap adds that Player to `player_map` again on the server" — a silent leak — [Issue #216](https://github.com/red-blox/zap/issues/216)
- #224 (Jul 14, 2026): Studio-only generated Promise stub references Promise before initialisation — [Issues](https://github.com/red-blox/zap/issues)
- #211 (Oct 26, 2025): namespaces can't access global types — [Issues](https://github.com/red-blox/zap/issues)
- #67: no 24/40/48/56/64-bit integer sizes (open since Feb 2024); #72: no channels (open since Feb 2024) — [Issues](https://github.com/red-blox/zap/issues)
- Sync events/functions: "If a synchronous function callback yields it will cause undefined and game-breaking behavior"; errors "will cause the packet to be dropped"; "Synchronous functions are not recommended, and should only be used when performance is critical" — [Functions](https://zap.redblox.dev/config/functions); [Events](https://zap.redblox.dev/config/events)
- "Zap does not support two way events"; functions are Client->Server->Client only — [Events](https://zap.redblox.dev/config/events); [Functions](https://zap.redblox.dev/config/functions)
- Unreliable events limited to 1000 bytes — [Events](https://zap.redblox.dev/config/events)
- Union types: cannot mix two number widths (e.g., `u8` and `u16`) in one union; optionals cannot be nested inside unions — [raw types.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/config/types.md)
- Non-optional `Instance` fields error on deserialize if the instance resolves to nil (e.g., not yet replicated) — [raw types.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/config/types.md)
- Syntax churn: v0.3.0 renamed types/keywords (breaking); v0.6.0 exit-code change; v0.6.10 moved remotes to `ReplicatedStorage/ZAP`; v0.6.24 deprecated `string` and `Instance (Model)` in favor of `string.utf8`/`string.binary` and `Instance.Model`; v0.6.28 changed the default event `type` to `Reliable` — [GitHub API releases p3](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=3); [releases page 2](https://github.com/red-blox/zap/releases?page=2); [GitHub API releases](https://api.github.com/repos/red-blox/zap/releases?per_page=100)
- Firing remotes above 60 Hz "can cause severe server crashes" per the docs' `manual_event_loop` warning — [raw options.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/config/options.md)
- Encryption was requested (#189) and closed the next day (Apr 17, 2025) — [search: closed issues](https://api.github.com/search/issues?q=repo:red-blox/zap+is:issue+is:closed)
- DevForum sentiment: InfiniteYield (Mar 25, 2024) argued buffer libraries don't add real security because exploiters "can literally get into the lua registry"; xxWars_chick (Sep 7, 2024) reported Blink outperforms both Zap and ByteNet in benchmarks; WizulousThe2nd (Sep 8, 2025) advised against premature networking optimization — [DevForum: Zap or ByteNet](https://devforum.roblox.com/t/zap-or-bytenet-performance-security/2888968)
- DevForum (Jul–Aug 2025): westside216 called Zap and ByteNet Max "both great modules" with equivalent functionality and pointed to Blink as faster "according to their benchmarking"; M_adpoint: "I haven't seen anything that Zap can do that ByteNet Max doesn't already offer" — [DevForum: Zap or ByteNet Max?](https://devforum.roblox.com/t/zap-or-bytenet-max/3820579)

### Inferences
- Zap's security story is "validation + obfuscation by buffers," not encryption; the docs' claim that Zap "validates all data recieved" means server-side runtime validation of client input is on by default, which is a strength versus the assignment's hypothesis of "no runtime validation by default."
- The monolithic-module scaling problem (#225) is the single most important risk for a large new project, and it has no upstream fix or maintainer acknowledgement as of Sept 20, 2026.

### Gaps
- No quantified threshold (number of events or generated line count) at which Roblox's bytecode limit is hit was given in #225's visible text.
- I found no maintainer statement on whether sharding is planned.

---

## Key Question 8: Installation methods

### Takeaway
Official docs list only Aftman (`aftman add red-blox/zap`) and downloading prebuilt binaries from GitHub Releases; Rokit works the same way because it installs from GitHub releases, but Rokit is not named in the docs. There is no Wally package (Zap is a code generator, not a runtime library) and no npm package.

### Cited Findings
- Install page: `$ aftman add red-blox/zap` and "You can get the latest version from GitHub Releases" — [raw install.md](https://raw.githubusercontent.com/red-blox/zap/0.6.x/docs/install.md); [Install](https://zap.redblox.dev/install.html)
- Prebuilt release assets for linux-x86_64, macos-aarch64, macos-x86_64, windows-x86_64 and a wasm tarball — [GitHub API releases/latest](https://api.github.com/repos/red-blox/zap/releases/latest)
- Rokit is "Next-generation toolchain manager for Roblox projects" that installs tools from GitHub releases; no Zap-specific Rokit instruction was found in official docs — [rojo-rbx/rokit](https://github.com/rojo-rbx/rokit); [WebSearch "rokit add red-blox/zap"](https://github.com/red-blox/zap)
- `@rbxts/zap` is not on npm (404) — [npm registry](https://registry.npmjs.org/@rbxts/zap)
- Generated output is plain Luau modules dropped into your project (no runtime dependency), with optional `.d.ts` for roblox-ts — [Getting Started](https://zap.redblox.dev/intro/getting-started); [Options](https://zap.redblox.dev/config/options)

### Inferences
- `rokit add red-blox/zap` should work since Rokit resolves GitHub release artifacts by `owner/repo` exactly as Aftman does, and Zap publishes platform-named zips; this is inferred, not documented by Zap.

### Gaps
- No official Rokit, Foreman, Studio plugin, or cargo-install instructions were found.

---

## Key Question 9: Zap version at the time of Blink's benchmark vs. now

### Takeaway
Blink's benchmark file has two substantive revisions: the original (test date May 6, 2024, the same day Blink's DevForum thread was posted) tested **Zap v0.6.3** (then current; v0.6.4 came June 24, 2024), and the April 30, 2025 update tested **Zap v0.6.20** (released April 13, 2025, then current). The current Zap is **v0.6.29 (June 23, 2026)**, nine patch releases later, including bitpacking (v0.6.24) which post-dates every published Blink comparison.

### Cited Findings
- Blink DevForum thread original post date: May 6, 2024; it links to the GitHub benchmarks but embeds no Zap numbers — [Blink DevForum thread](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0173/2959671)
- Benchmarks.md revision 720048b (committed Aug 10, 2024) records test date "May 6, 2024 at 18:20:25 UTC" with blink v0.11.1, zap v0.6.3, bytenet v0.4.3 — [Benchmarks.md @720048b](https://raw.githubusercontent.com/1Axen/blink/720048b/benchmark/Benchmarks.md); [file history](https://github.com/1Axen/blink/commits/main/benchmark/Benchmarks.md)
- Current Benchmarks.md: "Last updated April 30, 2025"; blink v0.17.1, zap v0.6.20, bytenet v0.4.3; a further commit on Oct 24, 2025 only converted line endings — [Blink Benchmarks.md](https://github.com/1Axen/blink/blob/main/benchmark/Benchmarks.md); [file history](https://github.com/1Axen/blink/commits/main/benchmark/Benchmarks.md)
- Zap v0.6.3 published 2024-03-14; v0.6.4 published 2024-06-24 — [GitHub API releases p6](https://api.github.com/repos/red-blox/zap/releases?per_page=5&page=6); [GitHub API releases p2](https://api.github.com/repos/red-blox/zap/releases?per_page=15&page=2)
- Zap v0.6.20 published 2025-04-13; v0.6.21 published 2025-06-22 — [GitHub API releases](https://api.github.com/repos/red-blox/zap/releases?per_page=100)
- Zap v0.6.29 published 2026-06-23 — [GitHub API releases/latest](https://api.github.com/repos/red-blox/zap/releases/latest)

### Inferences
- Both Blink benchmark snapshots tested the then-latest Zap, so neither was stale at publication; however, the newest snapshot is 17 months old as of Sept 2026 and predates Zap's bitpacking and other size optimizations.

### Gaps
- No Blink benchmark revision testing Zap v0.6.24+ was found.
