---
type: library
date: 2026-09-20
session: 14e4b904
title: Blink current state (researcher notes)
origin: Research subagent, deep-research session ee3b949e, 2026-09-20
description: Researcher notes behind the report: eight questions on Blink 0.18 and 1.0 with the full release timeline, IDL coverage, cited findings and gaps.
tags: [zap, blink, networking, snapshot]
---
# Blink (1Axen/blink) — Current State as of 2026-09-20
Up: [[Library]]

> Snapshot from 2026-09-20, kept verbatim for citations and detail. Current knowledge: [[Research/blink-current-state]]. If they disagree with this document, they win.

Research date: 2026-09-20. Primary sources: GitHub repo/releases/API, the docs site (https://1axen.github.io/blink/), the Roblox DevForum thread, VS Code Marketplace / Open VSX, pesde. A note on dating: GitHub's HTML release pages render dates without years for some entries, and the first pass produced wrong years for 2025 releases; every date below marked "(API)" comes from `published_at` in the GitHub REST API and is authoritative. Dates marked "(HTML, year inferred)" come from the releases HTML page with the year fixed by adjacent API-dated releases.

## Q1. Latest version, release cadence, and full version history (is Blink 1.0 yet?)

### Takeaway
Blink is NOT at a stable 1.0. As of 2026-09-20 it runs two parallel tracks: the stable `0.18.x` line (latest **v0.18.9, 2026-09-19**, marked "Latest" on GitHub) and a ground-up rewrite shipping as GitHub pre-releases (**v1.0.0-pre.10, 2026-09-19**, the tenth pre-release since 2026-01-14). There are 91 tags from v0.1.0 (2024-01-05) to today; cadence was very high in H1 2024, slowed to roughly monthly through 2025, and in 2026 has been bursty (a January–April cluster, then nothing May–August, then a burst in mid-September 2026).

### Cited Findings
- Repository created 2023-12-24; last push 2026-09-19; default branch `main`; MIT license; 182 stars, 36 forks, `open_issues_count` 20 — [GitHub API repo](https://api.github.com/repos/1Axen/blink)
- The tag list contains 91 tags: `v1.0.0-pre.10 … v1.0.0-pre.1, v0.18.9 … v0.18.0, v0.17.4 … v0.17.0, v0.16.0, v0.15.6 … v0.15.0, v0.15.0-rc.1, v0.14.15 … v0.14.0, v0.13.5 … v0.13.0, v0.12.3 … v0.12.0, v0.11.2 … v0.11.0, v0.10.5 … v0.10.0, v0.9.4 … v0.9.0, v0.8.2 … v0.8.0, v0.7.0, v0.6.3 … v0.6.0, v0.5.0, v0.4.4 … v0.4.0, v0.3.0, v0.2.0, v0.1.0` — [GitHub API tags](https://api.github.com/repos/1Axen/blink/tags?per_page=100)
- GitHub marks v0.18.9 as "Latest" (stable, 8 binary assets) and every `v1.0.0-pre.N` as "Pre-release" (5 assets) — [Releases page](https://github.com/1Axen/blink/releases)
- The `main` branch has 489 commits; the `rewrite` branch has 876 commits and was last updated 2026-09-19, same day as `main` — [main tree](https://github.com/1Axen/blink); [rewrite tree](https://github.com/1Axen/blink/tree/rewrite); [branches](https://github.com/1Axen/blink/branches)
- The 0.18 line runs on Lune (v0.18.5 "Upgraded to Lune 0.10.4"); the 1.0 rewrite runs on Lute (v1.0.0-pre.7 "Upgraded lute to 1.0.0"; rewrite branch has a `.lute` directory) — [Releases p.2](https://github.com/1Axen/blink/releases?page=2); [Releases p.1](https://github.com/1Axen/blink/releases); [rewrite tree](https://github.com/1Axen/blink/tree/rewrite)

#### Full release timeline (UTC dates)

| Version | Date | Notable changes | Source |
|---|---|---|---|
| v0.1.0 | 2024-01-05 (API) | Initial release | [API p.8](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=8) |
| v0.2.0 | 2024-01-07 (API) | "Added support for functions" | same |
| v0.3.0 | 2024-01-14 (API) | Unit tests; `Color3` type; scope/namespace definitions | same |
| v0.4.0–v0.4.2 | 2024-01-14 (API) | `Instance` support; type-referencing and struct Luau-type fixes | same |
| v0.4.3 | 2024-01-16 (API) | Lint preprocessors and version header in generated files | same |
| v0.4.4 | 2024-01-20 (API) | `Event.On` returns a disconnect function | [API p.7](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=7) |
| v0.5.0 | 2024-01-29 (API) | Unit tests, single-depth maps, tuples in event/function fields | same |
| v0.6.0–v0.6.1 | 2024-02-21 (API) | `f16` (float16) type; generator rewrite; fewer allocations | same |
| v0.6.2 | 2024-02-22 (API) | **Studio plugin introduced**; new error library | same |
| v0.6.3 | 2024-02-25 (API) | Fix server callbacks not passing `Player` | same |
| v0.7.0 | 2024-02-27 (API) | `unknown` primitive; `TypesOutput` option; call merging; plugin auto-indent | same |
| v0.8.0–v0.8.1 | 2024-03-03 (API) | New parser; `Casing` option; `vector`/`CFrame` support; inline references; array allocation | same |
| v0.8.2 | 2024-03-08 (API) | Optimized length types; plugin crash fixes | same |
| v0.9.0–v0.9.1 | 2024-03-16 (API) | Comments, nested scopes, struct generics, auto-bracket; optimized number types | same |
| v0.9.2 | 2024-03-17 (API) | "parsing 3.5x faster, generation 20x faster" | [API p.6](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=6) |
| v0.9.3 | 2024-03-18 (API) | Fixes (one-liners, float16 bodies, lowercase fields) | same |
| v0.9.4 | 2024-03-27 (API) | Tagged enums and type exports for standalone functions | same |
| v0.10.0 | 2024-03-27 (API) | **Breaking**: tagged enums & generics; "syntax changes requiring struct/enum/map keywords" | same |
| v0.10.1–v0.10.3 | 2024-03-27 → 03-29 (API) | Fixes (tagged-enum indexing, read cursor, name resolution) | same |
| v0.10.4–v0.10.5 | 2024-04-02 (API) | Buffer allocated at once for known sizes; standalone functions in types output; map resize fix | same |
| v0.11.0 | 2024-04-13 (API) | Plugin completion & live analysis; **multi-file support via `import`** | same |
| v0.11.1 | 2024-05-06 (API) | Type-variable optimisation; Future typing fix (same day as DevForum launch) | same |
| v0.11.2 | 2024-05-20 (API) | Plugin sidebar fix (CanvasGroup → Frame) | same |
| v0.12.0 | ~2024-05-31 (DevForum) | `set` type for flags; Linux/macOS builds added | [DevForum thread](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671) |
| v0.12.3 | 2024-06-04 (API) | Fixes | [API p.5](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=5) |
| v0.13.0 | 2024-06-09 (API) | `--watch` CLI option; `ManySync`/`ManyAsync` call types | same |
| v0.13.1 | 2024-06-19 (API) | CLI help; keywords usable as identifiers/fields; empty `Data`/`Return` | same |
| v0.13.2–v0.13.3 | 2024-06-24 (API) | Path parsing, watch mode, `set` parsing, import scope fixes | same |
| v0.13.4 | 2024-06-29 (API) | Fix empty-data client event generating invalid syntax | same |
| v0.13.5 | 2024-07-06 (API) | Plugin profiler menu; editor performance | same |
| v0.14.0 | 2024-07-29 (API) | **Event polling API**; struct merging with spread (`..foo`) | same |
| v0.14.1 | 2024-08-02 (API) | **TypeScript definition files**; polling `Next` → `Iter` rename | same |
| v0.14.5–v0.14.7 | 2024-08-15 → 08-17 (API) | Hotfixes (generic params in Luau types; race condition in functions) | [API p.4](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=4) |
| v0.14.8 | 2024-09-10 (API) | Plugin icon redesign; Promise type in TypeScript | same |
| v0.14.9–v0.14.10 | 2024-09-11 (API) | `--compact`/`-c` error output; TS remote-function return types | same |
| v0.14.11–v0.14.12 | 2024-09-21 (API) | Functions warn on exceeding 256-call queue, then `invoke` errors on queue exhaustion; ranges bounds-checked | same |
| v0.14.13 | 2024-09-26 (API) | `--watch` fix | same |
| v0.15.0–v0.15.1 | 2024-12-20 (API) | "Major update" to type system and serialization; unsafe-block offset fix | [API p.3](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=3) |
| v0.15.2 | 2025-01-16 (API) | Generics-solver crash hotfix | same |
| v0.15.3 | 2025-02-07 (API) | Stub functions trim buffer | same |
| v0.15.4 | 2025-02-13 (API) | String keys in structs/enums/sets | same |
| v0.15.5 | 2025-02-27 (API) | **`RemoteScope` option**; set perf/bandwidth improvements | same |
| v0.15.6 | 2025-03-11 (API) | Serdes hotfix for nil unknowns | same |
| v0.16.0 | 2025-03-18 (API) | `BrickColor`, `DateTime`, `DateTimeMillis` types | same |
| v0.17.0 | 2025-03-24 (API) | `SyncValidation` option; functions may yield in server listener | same |
| **v0.17.1** | **2025-04-29 (API)** | Client auto-replication no longer capped at 60 Hz — **this is the version in Benchmarks.md** | [API tag v0.17.1](https://api.github.com/repos/1Axen/blink/releases/tags/v0.17.1) |
| v0.17.2 | 2025-05-10 (HTML, year inferred) | Array upper-bound-only range parse fix | [Releases p.3](https://github.com/1Axen/blink/releases?page=3) |
| v0.17.3 | 2025-05-18 (HTML, year inferred) | `Poll` field deprecated in favour of `Call: Polling`; TS optionals emit `field?: type`; docs "Language" section rewritten | same |
| v0.17.4 | 2025-06-27 (API) | Plugin decimal-parsing fix | [API p.2](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=2) |
| v0.18.0 | 2025-08-01 (API) | Promise type inference; absolute paths in imports | same |
| v0.18.1 | 2025-08-11 (API) | Absolute output-path fix | same |
| v0.18.2 | 2025-09-29 (API) | TS generation respects `Call: Polling`; plugin toolbar sync | same |
| v0.18.3–v0.18.4 | 2025-09-30 → 10-01 (API) | Release packaging (zip → xz for non-Windows, gzip for Windows) | same |
| v0.18.5 | 2025-10-24 (API) | Lune 0.10.4; duplicate `RemoteScope` error; **`SyncValidation` on by default**; pesde publishing begins | same |
| v0.18.6 | 2025-10-24 (API) | Fix unit packs (tuples) generating invalid Luau | same |
| **v1.0.0-pre.1** | **2026-01-14 (API)** | **Major rewrite** (see Q2 for details; many breaking changes) | same |
| v1.0.0-pre.2 | 2026-01-17 (API) | Type-reference resolution; `..255` upper-range parsing; Windows diagnostics encoding | [API p.1](https://api.github.com/repos/1Axen/blink/releases?per_page=100) |
| v1.0.0-pre.3 | 2026-02-03 (API) | New import syntax: `from "path" import {a as b}` and `from "path" import * as m`; `step_replication` casing fix | same |
| v1.0.0-pre.4 | 2026-02-09 (API) | Fixed sending an empty buffer every frame; into-scope imports; empty functions | same |
| v0.18.7 | 2026-02-13 (API) | Fixed "out of local registers" from too many serdes functions; removed redundant `IsA` | same |
| v1.0.0-pre.5 | 2026-03-15 (API) | Batched events no longer exit early on first connected event | same |
| v0.18.8 | 2026-04-11 (API) | Plugin cursor/line-number/selection alignment; `DateTime`/`DateTimeMillis` read advanced 1 byte instead of 8 (fix); plugin autocomplete navigation | same |
| v1.0.0-pre.6 | 2026-04-11 (API) | `nil` singleton type exposed; array read optimisation; server deserialization exits early if player leaves; `integer` (int64) type behind an FFlag | same |
| v1.0.0-pre.7 | 2026-08-24 (API) | Lute 1.0.0; dedicated missing-delimiter syntax error; `from`/`as` usable as identifiers | same |
| v1.0.0-pre.8 | 2026-09-16 (API) | Removed stale `*_library` options and `stable`/`bitpack` attributes; CLI reports pre-release version; fixes #84 #90 #92 #94 #98 #100 | same |
| v1.0.0-pre.9 | 2026-09-18 (API) | Enum storage optimisation; **write validations disabled in `release` profile**; removed unimplemented `--watch`/`--yes`; `@export` on generics now errors; fixes for events received before first connection, malformed client buffer, departed-player saves | same |
| v0.18.9 | 2026-09-19 (API) | Validation error text says "or equal to"; NaN scalars/vectors no longer bypass inexact range validation | same |
| v1.0.0-pre.10 | 2026-09-19 (API) | `@profile("...")` attribute for profile-gated declarations; NaN bounds fix; exact vector-length validation fix | same |

### Inferences
- The 2026 stable releases (0.18.7/0.18.8/0.18.9) are bug-fix-only; all new features since January 2026 land only in the 1.0 pre-release track. A new project adopting 0.18.x today is adopting a maintenance-mode API.
- The 1.0 pre-release track was quiet from mid-April to late August 2026 (one release in ~4.5 months), then received four releases in five days (Sept 16–19) driven by a batch of ~20 issues filed by one external tester on 2026-09-15 (see Q6). The track is clearly still in active bug-fixing, not release-candidate hardening.
- There is no published target date for a stable 1.0 anywhere I found.

### Gaps
- Exact dates for v0.12.0–v0.12.2, v0.14.2–v0.14.4, v0.14.14–v0.14.15 and v0.15.0-rc.1 were not captured (API responses truncated); v0.12.0 is dated only via the DevForum announcement.
- No CHANGELOG file was seen in the repo root listing; release notes exist only on GitHub Releases.

## Q2. What the Blink IDL supports (0.18 stable vs 1.0 rewrite)

### Takeaway
0.18.x is a fairly complete IDL: sized ints/floats with ranges, strings/buffers with length bounds, vectors/CFrames with per-component encodings, Instances (with class filter), unknown, BrickColor/Color3/DateTime, structs (with spread-merge and generics), unit and tagged enums, maps, sets, arrays, optionals, type packs, scopes, imports, events with 5 call modes, functions with 3 yield modes, and ~12 options. The 1.0 rewrite changes the syntax substantially (everything becomes `type X = ...`, options are snake_case, exports live under `.exports`), adds literal types, true unions, recursive types, `u24/u48`, `integer`, `StreamedInstance`, `Enum`, named event parameters, `from: Both`, compile profiles and attributes, and REMOVES `f16`, unit `enum`, Promise/Future yield modes and (so far) TypeScript output.

### Cited Findings

#### 0.18.x types (docs site)
- Numbers: `u8`, `u16`, `u32`, `i8`, `i16`, `i32`, `f16`, `f32`, `f64`; ranges `u8(0..100)`, half-open `u8(..100)`, exact values; "The number of bits also corresponds to the cost of sending a particular number type over the network"; "The f16 type isn't natively supported by the buffer library, making it slower to read and write than other types." — [Types](https://1axen.github.io/blink/language/4-types)
- Strings/buffers: `string`, `string(3..20)`, `string(36)`, `buffer`, `buffer(..900)`; "Buffers allow you to pass your own custom serialized data while still taking advantage of blink's batching." — [Types](https://1axen.github.io/blink/language/4-types)
- Vectors: `vector`, `vector(0..1)` (magnitude range), `vector<i16>`, `vector<u8>`; "Since Luau stores vectors as three f32s internally, any encoding larger than a f32 (ex. f64) will have no real effect on the numerical precision." — [Types](https://1axen.github.io/blink/language/4-types)
- CFrames: `CFrame`, `CFrame<i16, f16>` (positional, rotational encodings); "Using an integer type for the rotational encoding will result in the rotation being zeroed out." — [Types](https://1axen.github.io/blink/language/4-types)
- Instances: `Instance`, `Instance(Player)`; "If a non-optional instance results in nil on the receiving side, it will raise a deserialization error, and the rest of the data will be dropped." — [Types](https://1axen.github.io/blink/language/4-types)
- Other: `boolean`, `BrickColor`, `Color3`, `DateTime`, `DateTimeMillis`, `unknown` — [Types](https://1axen.github.io/blink/language/4-types)
- Structs: `struct Entity { Health: u8(0..100), Position: vector, Rotation: u8 }`; optional fields `First: u8?`; merge/spread `struct foo_bar { ..foo }`; generics `struct Fragment<T> { Index: u8, Data: T }` — [Types](https://1axen.github.io/blink/language/4-types)
- Unit enums: `enum CharacterStatus = { Idling, Walking, Running, Jumping, Falling }`; tagged enums: `enum MouseEvent = "Type" { Move { Delta: vector, Position: vector }, Click { Button: enum { Left, Right, Middle }, Position: vector } }`; generic tagged `enum Union<A, B> = "Type" { A { Value: A }, B { Value: B } }` — [Types](https://1axen.github.io/blink/language/4-types)
- Maps: `map StringToNumber = { [string]: f64 }`, with size `{ [string]: f64 }(1..100)`, generic `map Map<K, V> = {[K]: V}`; Sets: `set Flags = { FeatureA, FeatureB, FeatureC }` ("map string keys to `true`"); Arrays: `string[]`, `string[25..50]`, `f64[1..50]`; Optionals: append `?` (`string(3..20)?`, `u8?`) — [Types](https://1axen.github.io/blink/language/4-types)
- Exports: `export struct MyInterface = { field: u8 }` generates standalone read/write functions; "Exports do not currently support Instances and Unknowns." — [Types](https://1axen.github.io/blink/language/4-types)
- Type packs/tuples for multiple event values: `Data: (u8, u16, u32)` — [Events](https://1axen.github.io/blink/language/5-events)
- Scopes: `scope ExampleScope { type InScopeType = u8  event InScopeEvent { ... } }`; access `Blink.ExampleScope.InScopeEvent.FireAll(0)`; types flatten with underscore `Blink.ExampleScope_InScopeType`; "Scopes automatically capture any definitions within their parent scopes." — [Scopes](https://1axen.github.io/blink/language/2-scopes)
- Imports: `import "./external"` / `import "./external" as "Common"`; imported file becomes a scope; referenced as `external.Type`; "In Roblox Studio, only sibling imports are supported" — [Imports](https://1axen.github.io/blink/language/3-imports); absolute import paths since v0.18.0 — [Releases p.2](https://github.com/1Axen/blink/releases?page=2)

#### 0.18.x events and functions
- Event fields: `From: Server|Client`; `Type: Reliable|Unreliable`; `Call: SingleSync|ManySync|SingleAsync|ManyAsync|Polling`; `Data: <type>` (optional). "Reliable - Events are guaranteed to arrive at their destination in the order they were sent in"; "Unreliable - Events are not guaranteed to arrive...or to arrive in the order they were sent in. They also have a maximum size of 1000 bytes"; "Sync events should be avoided unless performance is critical. Yielding or erroring in sync event can cause undefined and sometimes game-breaking behaviour." — [Events](https://1axen.github.io/blink/language/5-events)
- Generated API: client `blink.MyEvent.Fire(5)`; server `Fire(Player, 5)`, `FireAll(5)`, `FireList({Player}, 5)`, `FireExcept(Player, 5)`; listen `.On(function(...))` (Player first on server); polling `.Iter()` — [Events](https://1axen.github.io/blink/language/5-events); `On` returns a disconnect function since v0.4.4 — [API p.7](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=7)
- Functions (client→server only): `function MyFunction { Yield: Coroutine|Future|Promise, Data: f64, Return: f64 }`; client `blink.MyFunction.Invoke(5)` (Coroutine), `:Await()` (Future, redblox recommended), `:await()` (Promise, evaera's recommended); server `blink.MyFunction.On(function(Player, Value) return Value * 2 end)` — [Functions](https://1axen.github.io/blink/language/6-functions)

#### 0.18.x options
- `Casing` (default `Pascal`; `Pascal|Camel|Snake`); `ServerOutput`, `ClientOutput`, `TypesOutput` (paths); `Typescript` (default `false`, "generate TypeScript definition files alongside Luau files"); `UsePolling` (default `false`); `FutureLibrary`/`PromiseLibrary` (e.g. `"ReplicatedStorage.Packages.Future"`); `SyncValidation` (default `true`, "check whether a sync call yielded"); `WriteValidations` (default `false`, "check types when writing them (firing an event/invoking a function)"); `ManualReplication` (default `false`, "replicate events and functions automatically at the end of every frame"); `RemoteScope` (default `""`, e.g. `"PACKAGE"` → remote named `"PACKAGE_BLINK_RELIABLE_REMOTE"`) — [Options](https://1axen.github.io/blink/language/1-options)

#### 1.0 rewrite (pre-release) syntax — from release notes and `examples/` on the `rewrite` branch (there is no 1.0 documentation site)
- v1.0.0-pre.1 notes: "All user exports are now nested in a `.exports` table" (`blink.exports.my_event.fire(...)`); literal number/boolean/string types; union types (`number | string`, `Instance | Instance<"Model">`); string-literal unions replace unit enums; recursive types with generics; `StreamedInstance` replaces `Instance?`; `from: Both` for events; named event/function data; Promise/Future support removed; new `Enum` type; `i/u24`, `i/u48` added, `f16` removed; `.luaurc` aliases in imports; compilation profiles `dev`/`release`. Planned but not included at pre.1: "Bit packing, stable structs, sync validation, TypeScript output, batch max size option, glob imports, destructured imports, and token bucket rate limiting." — [v1.0.0-pre.1](https://github.com/1Axen/blink/releases/tag/v1.0.0-pre.1)
- `examples/types.blink` (rewrite): `type null = nil`; `type vec2 = vector<f32, f32, 0>`; `type unit_vector = vector(1)`; `type u_24 = u24`; `type int64 = integer`; `type fixed_blob = buffer(32)`; `type username = string(0..20)`; `type array = u8[0..255]`; `type fixed_array = u8[16]`; `type optional = username?`; `type any = unknown`; generic struct `type entity<C, T> = struct { id: u8, class: C, health: u8, data: T }` instantiated with a literal `type cat = entity<"cat", struct {meows: u16, purrs: u16}>`; recursive `type node<T> = struct { value: T, next: node<T>? }`; mutually recursive `tree<T>`/`forest<T> = tree<T>[]`; union `type class = "Tank" | "Healer" | "Assasin" | "Marksman"`; `purchases: map {[string]: purchase}`; sized map `map {[f64]: u16}(10)` — [types.blink](https://github.com/1Axen/blink/blob/rewrite/examples/types.blink)
- `examples/remotes.blink` (rewrite): `event reliable = { from: Client, type: Reliable, call: SingleSync, data: (value: u8, foo, bar: bar) }`; `from: Both`; `function request = { data: (foo: foo, bar: bar), return: (u8, string) }`; header comment lists `from: Client | Server | Both`, `type: Reliable | Unreliable`, `call: SingleSync | SingleAsync | ManySync | ManyAsync | Polling` — [remotes.blink](https://github.com/1Axen/blink/blob/rewrite/examples/remotes.blink)
- `examples/options.blink` (rewrite): `option types_output = "./out/types"`, `option client_output`, `option server_output`, `option casing = "snake_case" -- camelCase, PascalCase`, `option manual_replication = true` — [options.blink](https://github.com/1Axen/blink/blob/rewrite/examples/options.blink)
- Other rewrite examples exist: `exports.blink`, `generics.blink`, `imports.blink`, `profiles.blink`, `roblox.blink`, `structs.blink`, `unions.blink`, plus `libs/` and `.luaurc` — [examples dir](https://github.com/1Axen/blink/tree/rewrite/examples)
- pre.3 added `from "path" import {linked_list as list, math.pi as PI}` and `from "path" import * as module`; pre.10 added `@profile("...")`; pre.9 makes `@export` on generic types a compiler error; pre.8 removed stale `*_library` options and `stable`/`bitpack` attributes — [Releases](https://github.com/1Axen/blink/releases)
- Maintainer on tagged enums (0.18): they "aren't true unions but tables with tag fields, useful for union type emulation only" and cannot be map keys (2026-03-16) — [DevForum p.8](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=8)

### Inferences
- Bit-packing is still not implemented in 1.0: pre.8 removed the `bitpack` attribute as "stale" and issue #105 "Implement @bitpack annotation" (2026-09-15) is open.
- TypeScript output is present in 0.18 (`Typescript` option) but absent from every 1.0 pre-release note through pre.10; a roblox-ts project should treat the 1.0 track as Luau-only for now.
- The 0.18 docs' Introduction page shows lowercase field keys (`from:`, `type:`, `call:`, `data:`) while the Events page shows capitalised (`From:`, `Type:`); v0.13.1 made "keywords as identifiers/fields" so both may parse, but a newcomer will notice the inconsistency.

### Gaps
- No authoritative 1.0 reference exists; the full 1.0 option list (beyond the five in `options.blink`) and the exact semantics of profiles/attributes are only inferable from release notes.
- Whether 1.0's `unknown`, `Enum`, and `StreamedInstance` are supported inside `@export`ed types was not verified.

## Q3. Output targets and tooling (Luau, TypeScript, types file, CLI, Studio plugin, VS Code, playground)

### Takeaway
Blink emits a server Luau module, a client Luau module and (optionally) a separate types module; in 0.18 it can also emit TypeScript `.d.ts` files for roblox-ts. Tooling is a CLI binary (Lune-based in 0.18, Lute-based in 1.0), a Roblox Studio plugin with a built-in editor, and a community-published VS Code extension (`checkraisefold.blink-vscode`, "syntax highlighting & intellisense", forked from zap-vscode). I found no language server, no web playground, and no npm/Wally packages.

### Cited Findings
- Running `blink FILE_NAME` produces server and client Luau files at `ServerOutput`/`ClientOutput`; "Blink returns an immutable table with all of your events and functions"; usage `local Net = require(Path.To.Server) Net.MyFirstEvent.FireAll("Hello World")` — [Introduction](https://1axen.github.io/blink/getting-started/2-introduction)
- `TypesOutput` option (types file) added in v0.7.0 (2024-02-27) — [API p.7](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=7); `Typescript` option (default false) generates definition files alongside Luau — [Options](https://1axen.github.io/blink/language/1-options); TS definition support first shipped in v0.14.1 (2024-08-02) — [API p.5](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=5)
- CLI docs cover only `blink file-name` (looks for `.blink` or `.txt`) and `blink file-name --watch` (recompiles when the file or nested imports change) — [CLI](https://1axen.github.io/blink/getting-started/3-cli); `--compact`/`-c` compact errors exist since v0.14.9 but are not on that page — [API p.4](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=4); 1.0 pre.9 "Removed unimplemented CLI options (`--watch`, `--yes`)" — [Releases](https://github.com/1Axen/blink/releases)
- Studio plugin: "you will be prompted to give it access to inject scripts, this is needed to be able to generate output files"; the editor "has various rudimentary intellisense features built-in"; a side menu manages description files; "Generate" prompts for an output location and creates "a Folder containing your networking modules"; "Make sure to select a location that is accessible to both the client and server" — [Plugin](https://1axen.github.io/blink/getting-started/4-plugin); Creator Store asset id `77231976488966` ("Blink-Editor") or GitHub Releases — [Installation](https://1axen.github.io/blink/getting-started/1-installation)
- VS Code: repository `blink-vscode` — "Syntax highlighting and intellisense for the Blink IDL", "based on zap-vscode", extension ID `checkraisefold.blink-vscode`, also on Open VSX; MIT — [blink-vscode README](https://github.com/1Axen/blink-vscode); Marketplace: version 0.1.12, 1,631 installs, 5/5 (1 review), last updated 2026-09-07 — [Marketplace](https://marketplace.visualstudio.com/items?itemName=checkraisefold.blink-vscode); Open VSX: 0.1.12 published 2026-04-11, 5,362 downloads, 15 versions (0.0.1–0.1.12) — [Open VSX API](https://open-vsx.org/api/checkraisefold/blink-vscode); `checkraisefold` is also a blink contributor (1 commit) — [Contributors API](https://api.github.com/repos/1Axen/blink/contributors?per_page=30)
- A third-party Zed editor extension (`okhalri/zed-blink`, grammar `okhalri/tree-sitter-blink`) was submitted to the Zed extensions registry — [zed-industries/extensions PR #6646](https://github.com/zed-industries/extensions/pull/6646)
- Repo `src/` layout on main: `CLI/`, `Generator/`, `Modules/`, `Templates/` (`Base.luau`, `Client.luau`, `Server.luau`), `Lexer.luau`, `Parser.luau`, `Settings.luau` — [src](https://github.com/1Axen/blink/tree/main/src); [Templates](https://github.com/1Axen/blink/tree/main/src/Templates)
- README credits: "Zap (range and array syntax), ArvidSilverlock (float16 implementation), and Microsoft's VSCode icons under CC BY 4.0" — [README](https://github.com/1Axen/blink)

### Inferences
- The VS Code extension's "intellisense" is editor-side completion inherited from zap-vscode; nothing in the README, Marketplace listing, or 1Axen's repo list mentions a Language Server Protocol implementation, diagnostics, or go-to-definition. The claim in the brief that "Blink has a language server" is not supported by anything I found.
- The extension's marketplace update on 2026-09-07 postdates the Open VSX publish (2026-04-11), so it may have been rebuilt for the 1.0 syntax; but nothing states which syntax version (0.18 vs 1.0) it targets.

### Gaps
- Could not load the Creator Store plugin page (JS-rendered), so plugin install counts/last-updated are unknown.
- No source states whether the VS Code extension supports 1.0 pre-release syntax.
- No web playground found (searched; nothing on the docs site or README).

## Q4. How Blink batches and sends packets; performance design

### Takeaway
Blink serialises every fired event into a per-destination growable buffer (64 bytes initial, ×1.5 growth) and flushes those buffers through one reliable `RemoteEvent` and one `UnreliableRemoteEvent` per scope "at the end of every frame" (a `step_replication`/`StepReplication` function you can call yourself with `ManualReplication`). Unreliable packets are capped at 1000 bytes by the docs; the function-invoke path uses a 256-slot ring of pending calls; there is a 256-entry queue for events received before a listener connects. Batching is the stated reason it beats generalised libraries; the maintainer's own benchmark (v0.17.1) shows Blink ≈ Zap on bandwidth and modestly ahead on CPU.

### Cited Findings
- `ManualReplication` (default false) "Controls if Blink will replicate events and functions automatically at the end of every frame"; `RemoteScope = "PACKAGE"` names the remote `"PACKAGE_BLINK_RELIABLE_REMOTE"` — [Options](https://1axen.github.io/blink/language/1-options)
- v0.17.1: "Client side automatic replication is no longer capped at 60 Hz" — [API tag v0.17.1](https://api.github.com/repos/1Axen/blink/releases/tags/v0.17.1)
- Unreliable events "have a maximum size of 1000 bytes" — [Events](https://1axen.github.io/blink/language/5-events)
- `Base.luau` template: `SendBuffer` starts at 64 bytes and is resized ×1.5 when exceeded via an `Allocate()` cursor function; separate `Reliable`/`Unreliable` queues each `table.create(256)`; a `Calls` table `table.create(256)` with `Invoke()` cycling invocation IDs 0–255 with wraparound — [Base.luau](https://raw.githubusercontent.com/1Axen/blink/main/src/Templates/Base.luau)
- `Server.luau` template: `PlayersMap: {[Player]: BufferSave}` holding per-player `Send = {Buffer, Cursor, Instances}`; `StepReplication()` copies the buffer with `buffer.copy()`, fires `Reliable:FireClient()`, resets the buffer to 64 bytes; `PlayerRemoving` clears `PlayersMap[Player]`; a separate `UnreliableRemoteEvent` is used for unreliable traffic — [Server.luau](https://raw.githubusercontent.com/1Axen/blink/main/src/Templates/Server.luau)
- v0.14.11/v0.14.12: "Functions warn on exceeding 256-call queue"; "`invoke` now errors on queue exhaustion" — [API p.4](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=4)
- Maintainer (2025-09-07): Blink "leverages built-in Remote queuing and maintains internal event queue until client connects"; (2026-01-03) recommends "routing all network traffic through Blink to maximize builtin event batching benefits" — [DevForum p.4](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=4); [DevForum p.8](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=8)
- Maintainer on ranges and cost (2025-05-30): dynamic-length types with max ≤255 use a u8 length prefix; >65535 use u32; otherwise "Performance differences otherwise negligible" — [DevForum p.4](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=4)
- Instances travel alongside the buffer (the `Instances` array in `BufferSave`); a nil non-optional instance raises a deserialization error and "the rest of the data will be dropped" — [Server.luau](https://raw.githubusercontent.com/1Axen/blink/main/src/Templates/Server.luau); [Types](https://1axen.github.io/blink/language/4-types)
- 1.0 replication fixes: pre.4 "Fixed sending empty buffer every frame"; pre.5 "Batched events no longer exit early on first connected event"; pre.6 "Server deserialization loop exits early if player leaves"; pre.9 fixed "Events received before first connection not consumed" and "Client-side serialization leaving buffer malformed"; pre.9 "Write validations disabled in release profile" — [Releases](https://github.com/1Axen/blink/releases)
- Security framing: data validation on the receiving side, and compression makes traffic "significantly harder to snoop on" (RemoteSpy-style tools) — [README](https://github.com/1Axen/blink); [DevForum OP](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671)
- Benchmarks.md ("Last Updated 2025-04-30 19:45:09 UTC", "v0.17.1", AMD Ryzen 9 7900X, 34 GB RAM, "firing the event 1000 times per frame with the same data" for 10 s, zero packet loss): Entities test — Blink 42 FPS median / 41.81 Kbps, Zap 39 / 41.71, ByteNet 32 / 41.64, Roblox 16 / 559,364.31 Kbps; Booleans test — Blink 97 / 7.91, Zap 52 / 8.10, ByteNet 35 / 8.11, Roblox 21 / 353,107.13 — [Benchmarks.md](https://github.com/1Axen/blink/blob/main/benchmark/Benchmarks.md)
- Benchmarks.md history: created 2024-08-10 ("Updated benchmarks to new layout"), updated 2025-04-30 ("chore: update benchmarks"), 2025-10-24 (line endings only) — [Benchmarks.md commits](https://github.com/1Axen/blink/commits/main/benchmark/Benchmarks.md)
- DevForum OP (2024-05-06) headline claims "1.6-3.7x faster than ROBLOX" and "1000x less bandwidth than ROBLOX"; v0.11.1 was released the same day (2024-05-06) — [DevForum topic JSON](https://devforum.roblox.com/t/2959671.json); [API p.6](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=6)

### Inferences
- **Benchmark version vs. now**: the benchmark table in the repo was last measured with **v0.17.1 (released 2025-04-29, measured 2025-04-30)**; the current stable is v0.18.9 and current pre-release is v1.0.0-pre.10 (both 2026-09-19). The original DevForum performance claims were made when **v0.11.1** was current (May 2024). The 2024-08-10 benchmark layout commit would have been against ~v0.14.1–v0.14.2, but the version used then is not recorded.
- The benchmark is a maintainer-run microbenchmark (1000 fires per frame of identical data) and shows Blink and Zap within ~0.2 % on bandwidth; the CPU gap is meaningful only in the boolean-heavy case. It is not evidence about real-game workloads.
- The 256-slot invoke ring implies at most 256 in-flight remote-function calls per client; with no timeout/cancellation (open issue #107) a server handler that never returns will leak slots until wraparound.

### Gaps
- The exact RunService signal used for the automatic flush (Heartbeat vs PostSimulation) was not confirmed; both template fetches were truncated before that code.
- No fragmentation logic for oversized reliable packets was observed or documented; whether a >1000-byte unreliable payload errors, is dropped, or is promoted to reliable is undocumented.
- No third-party or independent benchmark of Blink 0.18/1.0 was found.

## Q5. Documentation coverage and quality

### Takeaway
The docs site (Starlight-style, 11 pages) is short, readable, and accurate for 0.18.x syntax, but thin: the CLI page documents one flag, the TypeScript path gets one sentence, there is nothing on replication internals, security/validation behaviour, migration, or the 1.0 rewrite (which has no docs at all beyond release notes and example files). Newcomers on the DevForum report finding the docs hard to learn from.

### Cited Findings
- Site map: Home; Getting Started → Installation, Introduction, Command-Line Usage, Roblox Studio Plugin; Blink's Language → Options, Scopes, Imports, Types, Events, Functions — [Docs home](https://1axen.github.io/blink/)
- Home repeats README claims and points to GitHub for benchmarks; no architecture or "how it works" page — [Docs home](https://1axen.github.io/blink/)
- Introduction gives a single `MyFirstEvent` example, server/client `require` snippets and "Blink's language is really simple"; "The provided content contains no TypeScript/roblox-ts usage information" — [Introduction](https://1axen.github.io/blink/getting-started/2-introduction)
- CLI page documents only `blink file-name` and `--watch` — [CLI](https://1axen.github.io/blink/getting-started/3-cli)
- Functions page: "The documentation does not specify timeout configurations or detailed limitations" — [Functions](https://1axen.github.io/blink/language/6-functions)
- Options page still documents `FutureLibrary`, `PromiseLibrary`, `UsePolling` (removed/replaced in 1.0) — [Options](https://1axen.github.io/blink/language/1-options); Types page still documents `f16` and `enum` keyword (removed/replaced in 1.0) — [Types](https://1axen.github.io/blink/language/4-types)
- The `rewrite` branch has no `docs/` directory (top level: `.github, .lute, .typedefs, .vscode, buildconfig, cli, compiler, examples, libs, plugin, test, vendor`) — [rewrite tree](https://github.com/1Axen/blink/tree/rewrite)
- v0.17.3 (2025-05): "Language syntax section completely revised for improved clarity" — [Releases p.3](https://github.com/1Axen/blink/releases?page=3)
- User (2026-01-02) "Requested YouTube tutorials, citing difficulty understanding documentation" — [DevForum p.8](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=8); user (2025-05-25) "Recommends ByteNet for beginners as an alternative that doesn't require learning a new language" — [DevForum p.4](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=4)
- The docs are indexed by the Context7 LLM-docs aggregator — [Context7](https://context7.com/websites/1axen_github_io_blink)

### Inferences
- Gaps a newcomer will hit: (1) no explanation of what the generated code does per frame or how to use `ManualReplication`; (2) no roblox-ts walkthrough despite the `Typescript` option; (3) no guidance on `WriteValidations`/validation-failure behaviour or on what happens to a malformed client packet; (4) no 0.18 → 1.0 migration guide, and no signal on the docs site that a rewrite exists; (5) the CLI page omits `--compact`; (6) Introduction vs Events casing inconsistency.
- Anyone starting on 1.0 pre-releases must learn the syntax from `examples/*.blink` and release notes.

### Gaps
- I did not evaluate the Studio plugin's in-editor help text or the generated code's inline comments.

## Q6. Maintenance health (maintainer, contributors, activity, issues, responsiveness, roadmap)

### Takeaway
Blink is a one-person project: 1Axen ("Axen", DevForum @Ax3nx, "from Bloxware, based in Bulgaria") authored 205 of ~232 counted contributions; 12 other contributors have 1–7 commits each. Activity in 2026 is bursty rather than continuous, but issue response is fast when the maintainer is active (a batch of ~20 issues filed 2026-09-15 was mostly closed within 1–4 days and shipped in three pre-releases). There is no formal roadmap; the open "rewrite"-labelled issues are the de facto roadmap for 1.0.

### Cited Findings
- Profile: "Axen from Bloxware, based in Bulgaria", X @AxenRBX, Bluesky @axen.dev; other repos include `Secure-Cast` (30 stars) and `blink-vscode` — [1Axen repos](https://github.com/1Axen?tab=repositories)
- Contributors (13): 1Axen 205, C6H15 7, Tazmondo 4, bmcq-0 4, abidbmt 3, ffrostfall 2, TaylorsRus 1, zarchify 1, alihsaas 1, ari-party 1, checkraisefold 1, daimond113 1, dependabot 1 — [Contributors API](https://api.github.com/repos/1Axen/blink/contributors?per_page=30)
- `main` commit density: ~3 commits Jul–Sep 2026, ~12 in Apr–Sep 2026; external contributions from zarchify (Oct 2025, docs), abidbmt (Nov 2025), ari-party (Jan 2026), C6H15 (Apr 2026 plugin cursor/UI fixes) — [Commits](https://github.com/1Axen/blink/commits/main)
- `rewrite` branch: 876 commits, updated 2026-09-19 — [rewrite tree](https://github.com/1Axen/blink/tree/rewrite)
- Open issues: 19 issues + 1 PR (#88); 2 opened by 1Axen (#111, #95); 10 have zero comments; oldest open is #12 "Plugin lags with larger config files" (2024-07-02) — [Issues API](https://api.github.com/repos/1Axen/blink/issues?state=open&per_page=50); [Issues](https://github.com/1Axen/blink/issues)
- Recent open issues (all labelled `enhancement`/`rewrite` unless noted): #111 "Use a thread pool for Many* events" (1Axen, 2026-09-18); #109 non-fatal warnings; #108 compile-time payload size analysis; #107 "invoke: timeout, cancellation, slot recovery"; #106 visibility control for declarations; #105 "Implement @bitpack annotation"; #104 fixed-point/quantized numerals; #102 error policy for invalid incoming data; #101 deterministic output for event IDs (all kaan650, 2026-09-15); #95 "Self-recursive struct validation bug" (`bug`); #81 "NOOP needs modification for stories" (`bug`, 2026-04-06); #78 "Struct merging not working v1.0.0-pre.2" (2026-02-15) — [Issues](https://github.com/1Axen/blink/issues)
- Closed issues: 50 total; recent closures: #110 (2026-09-15 → 09-19), #103 (→09-18), #100 (→09-16), #99 (→09-17), #98 (→09-16), #97 (→09-17), #96 (→09-17), #94 (→09-16), #93 (→09-18), #92 (→09-16), #91 (→09-17), #90 (→09-16); slower older ones: #84 (2026-04-12 → 2026-09-16), #72 (2025-11-08 → 2026-02-11), #69 (2025-10-30 → 2026-02-13), #77 (2026-01-19 → 2026-03-29) — [Closed issues search API](https://api.github.com/search/issues?q=repo:1Axen/blink+is:issue+is:closed)
- Pre-release notes cross-reference those issues (pre.8 "fixes #92, #84, #94, #90, #98, #100") — [Releases](https://github.com/1Axen/blink/releases)
- DevForum thread: created 2024-05-06 21:59 UTC; 162 posts, 114 replies, 29,189 views, 263 likes, 40 participants; last post 2026-09-19 (0.18.9 announcement); OP last edited 2025-10-24 (title carries "0.18.5") — [Topic JSON](https://devforum.roblox.com/t/2959671.json); [DevForum p.9](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=9)
- Maintainer replies on the thread are typically same-day (e.g. 2025-06-21, 2025-09-06/07, 2025-09-21, 2026-01-03, 2026-03-16, 2026-03-19, 2026-04-08) — [DevForum p.4](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=4); [DevForum p.8](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=8)
- pesde package `1axen/blink`, target Lune, latest 0.18.9 — [pesde](https://pesde.dev/packages/1axen/blink)

### Inferences
- The 1.0 pre-releases have not been announced on the DevForum thread (pages 8–9 covering Sept 2025–Sept 2026 contain only the 0.18.5 and 0.18.9 announcements), so the rewrite is effectively GitHub-only and less battle-tested by the wider community.
- Bus factor is 1. The pattern of multi-month silences (mid-April → late-August 2026 on the 1.0 track) followed by bursts suggests availability-driven rather than scheduled development.
- The 2026-09-15 issue batch reads like a structured audit of the pre-release (numeric ranges unenforced, validation error corrupting the buffer, `vector(range)` runtime crash, examples failing to compile), i.e. pre.7 still had basic correctness bugs; pre.8–pre.10 fixed most of them within days.

### Gaps
- No stated roadmap document, milestone, or target date for stable 1.0 was found on GitHub, the docs, or the DevForum.
- DevForum pages 5 and 7 (Sept 2025) were not read; page 6 is entirely a side argument about a third-party "Secure-Blink" wrapper, not Blink itself.

## Q7. Known limitations, complaints, footguns

### Takeaway
The recurring pain points are: the Studio plugin editor freezes on files beyond ~150–800 lines (open since July 2024); sync callbacks that yield cause undefined behaviour and `Single*` listeners silently replace earlier connections; tagged enums are not real unions; a nil non-optional Instance drops the rest of the packet; the 256-slot invoke queue has no timeout; and the 1.0 rewrite is a large breaking change with no migration guide and known correctness bugs still being fixed in September 2026.

### Cited Findings
- Plugin performance: issue #12 "Plugin lags with larger config files" open since 2024-07-02 — [Issues API](https://api.github.com/repos/1Axen/blink/issues?state=open&per_page=50); user (2025-08-13): editor "begins to freeze every time i type something" after ~150 lines — [DevForum p.4](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=4); user (2026-07-20): at "800 lines" typing delays of "around a second" per character — [DevForum p.9](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=9)
- Plugin constraints: script-injection permission required; only sibling imports in Studio; output must be in a shared location — [Plugin](https://1axen.github.io/blink/getting-started/4-plugin); [Imports](https://1axen.github.io/blink/language/3-imports); users asked for auto-recompile / updating existing output rather than regenerating (2025-05-30, 2026-03-22) — [DevForum p.4](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=4); [DevForum p.8](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=8)
- Third-party opinion (2025-05-28): "Blink is more optimized and has the cleaner interface" but you must "generate new modules each time you add an event" and it "can't generate modules with attributes, which is annoying if you have plugins like SimpleComplete" — [DevForum "Best Network library" #37](https://devforum.roblox.com/t/best-network-library/3667044/37)
- Sync semantics: "Yielding or erroring in sync event can cause undefined and sometimes game-breaking behaviour" — [Events](https://1axen.github.io/blink/language/5-events); maintainer (2026-04-08): validation "warns only when yielding causes undefined behavior"; user (2026-04-09): "Single callbacks override previous connections rather than throw errors" — [DevForum p.8](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=8); a "buffer access out of bounds" report was diagnosed as yielding in a sync listener (2025-09-21) — [DevForum p.4](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=4)
- Type-system limits: tagged enums are tables with a tag field, not unions, and cannot be map keys (2026-03-16) — [DevForum p.8](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=8); "Exports do not currently support Instances and Unknowns"; nil non-optional Instance → deserialization error, rest of data dropped; `f16` slower than native types; integer rotational encoding zeroes rotation — [Types](https://1axen.github.io/blink/language/4-types); unreliable max 1000 bytes — [Events](https://1axen.github.io/blink/language/5-events)
- Generated-code scaling: v0.18.7 "Fixed 'out of local registers' error from excessive serdes functions"; issue #69 "Registry exhaustion" (2025-10-30 → 2026-02-13) — [Releases](https://github.com/1Axen/blink/releases); [Closed issues](https://api.github.com/search/issues?q=repo:1Axen/blink+is:issue+is:closed)
- Function limits: 256-call queue, `invoke` errors on exhaustion (v0.14.12); no timeout/cancellation (open #107) — [API p.4](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=4); [Issues](https://github.com/1Axen/blink/issues)
- Stale-output footgun: a `writeu8` type error was resolved by "User needed to recompile after event data changes" (2025-09-06) — [DevForum p.4](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=4)
- Breaking changes history: v0.10.0 required `struct`/`enum`/`map` keywords; v0.17.3 deprecated `Poll` for `Call: Polling`; v1.0.0-pre.1 nested all exports under `.exports`, removed Promise/Future and `f16`, replaced unit enums with string-literal unions, replaced `Instance?` with `StreamedInstance`, redesigned syntax; pre.9 removed `--watch` and disables write validations in `release` — [API p.6](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=6); [Releases p.3](https://github.com/1Axen/blink/releases?page=3); [v1.0.0-pre.1](https://github.com/1Axen/blink/releases/tag/v1.0.0-pre.1); [Releases](https://github.com/1Axen/blink/releases)
- 1.0 pre-release bugs found 2026-09-15: #90 "Numeric ranges unenforced", #91 "Validation error corrupts buffer", #94 "vector(range) crashes at runtime", #93 "Messages before on() connected", #92 "players_map incomplete on load", #98 "Examples fail to compile", #100 "Diagnostic codes collide", #96 "@export ignored on generic types" (all closed by 2026-09-19) — [Closed issues](https://api.github.com/search/issues?q=repo:1Axen/blink+is:issue+is:closed)
- Error-message quality: v0.14.9 added compact errors; pre.7 added a "dedicated syntax error for missing delimiters with contextual messaging"; #109 requests a non-fatal warning level — [API p.4](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=4); [Releases](https://github.com/1Axen/blink/releases); [Issues](https://github.com/1Axen/blink/issues)
- Benchmark misreads happen: a user (2026-03-19) questioned Blink's value from the FPS table until told higher is better — [DevForum p.8](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=8)
- A third-party "Secure-Blink" encryption wrapper (RC4) posted in the thread drew security criticism (hookable checks, no handshake) on 2025-09-29; it is not part of Blink — [DevForum p.6](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=6)

### Inferences
- For a brand-new project the biggest practical risk is version choice: 0.18.9 is stable but frozen and its syntax will not carry into 1.0; 1.0 is where all development is, but it has no docs, no TypeScript, and was still fixing basic validation bugs a week before this report.
- "Compression makes traffic harder to snoop" is obfuscation-by-format, not encryption; the docs do not claim otherwise, but the DevForum thread shows users conflating the two.

### Gaps
- No source quantifies generated-module size for 0.18 vs 1.0 (the register-exhaustion bug implies large files exist, but no numbers).
- No independent security review of Blink's validation path was found.

## Q8. Installation methods

### Takeaway
Officially: Rokit (`rokit add 1Axen/blink`), pesde (`pesde add --dev 1axen/blink`, 0.18.5+), pre-built binaries from GitHub Releases (Windows/macOS/Linux), and the Studio plugin (Creator Store or GitHub). No Wally or npm package exists; Aftman is not documented.

### Cited Findings
- "Primary Method: Rokit — `rokit add 1Axen/blink`; update `rokit update 1Axen/blink`"; "pesde (version 0.18.5+): `pesde add --dev 1axen/blink` then `pesde install`"; "download pre-built binaries directly from the GitHub Releases page"; Studio plugin via Creator Store asset `77231976488966/Blink-Editor` or GitHub Releases; "The page does not mention Aftman, Wally, or npm" — [Installation](https://1axen.github.io/blink/getting-started/1-installation)
- pesde page: `1axen/blink`, latest 0.18.9, target Lune, `pesde add 1axen/blink`, `pesde x 1axen/blink` — [pesde](https://pesde.dev/packages/1axen/blink)
- Stable releases attach 8 assets, pre-releases 5; v0.18.4 "Switch to xz for non-windows releases, and gzip for windows releases"; Linux/macOS builds since v0.12.0 (2024-05-31) — [Releases](https://github.com/1Axen/blink/releases); [Releases p.2](https://github.com/1Axen/blink/releases?page=2); [DevForum](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671)
- Repo ships `rokit.toml` and `pesde.toml` — [README](https://github.com/1Axen/blink); a 2026-05-24 issue #87 "Rokit CLI error" was closed same day — [Closed issues](https://api.github.com/search/issues?q=repo:1Axen/blink+is:issue+is:closed)
- VS Code extension via Marketplace (`checkraisefold.blink-vscode`) or Open VSX — [Marketplace](https://marketplace.visualstudio.com/items?itemName=checkraisefold.blink-vscode); [Open VSX](https://open-vsx.org/api/checkraisefold/blink-vscode)
- npm search for an `@rbxts`/Blink package returned nothing Blink-related — [npm search results](https://www.npmjs.com/org/rbxts)

### Inferences
- Because Rokit installs from GitHub Releases, `rokit add 1Axen/blink` will resolve to the "Latest" (stable 0.18.9) release; using a 1.0 pre-release presumably requires pinning the tag explicitly (e.g. `1Axen/blink@1.0.0-pre.10`). Not verified.
- roblox-ts projects consume Blink by running the CLI (or plugin) and importing the emitted `.d.ts`; there is no npm distribution.

### Gaps
- Whether Rokit/Aftman resolve pre-release tags by default was not verified.
- Plugin install count and last-updated date on the Creator Store could not be retrieved.
