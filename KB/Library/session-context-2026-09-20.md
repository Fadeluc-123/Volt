---
type: library
date: 2026-09-20
session: 14e4b904
title: Session context 2026-09-20: Zap vs Blink research and the decision to build Volt
origin: Claude Code session ee3b949e with Mike, 2026-09-20
description: The consolidated knowledge of the 2026-09-20 research session, tagged by kind: decisions, facts, explanations, preferences, requirements, open questions.
tags: [zap, blink, networking, snapshot]
---
# Session context: 2026-09-20, Zap vs Blink research and the decision to build Volt
Up: [[Library]]

> Snapshot from 2026-09-20, kept verbatim for citations and detail. Current knowledge: [[Decisions/build-from-scratch-not-fork]], [[Decisions/volt-goals]], [[Research/how-buffer-networking-works]]. If they disagree with this document, they win.

This file consolidates everything discussed in the 2026-09-20 Claude Code session with Mike (mike@whiteoak.studio). It is written for a knowledge-base ingestion agent. Each section is self-contained and marked with what kind of knowledge it holds: decision, fact, explanation, preference, or open question. The full raw transcript, if present, is in `transcript/`. The research report and notes are in `reference/`. The forward-looking task list is in `HANDOFF.md`.

---

## 1. Session summary

**Kind: decision log**

1. Mike asked for research comparing Zap (red-blox/zap) and Blink (1Axen/blink) for a brand-new Roblox project, excluding ByteNet. He leaned Zap because its docs are clearer. Four research subagents and one report writer produced `reference/reports/Zap vs Blink for Roblox networking.md`. Recommendation: Zap 0.6.29, revisit when Blink 1.0 ships stable.
2. Mike asked how serialization works, whether Zap needs an external compiler, for a Blink client and server example with generated code, and why a compiler is needed at all. Answered in section 4.
3. Mike asked whether building his own package is a good idea. Assessment in section 5: build the runtime and hand-written packets if desired, do not build a compiler yet, and fork Blink if he wants Blink's approach under his control.
4. Mike asked how Blink's compiler generates code. Explained from source in section 6.
5. Mike objected to `_G` in generated runtime code. Findings in section 7: both libraries emit a `_G` duplicate-instance guard at require time; Blink 1.0 dropped it.
6. Mike decided to build his own package from scratch, using Blink and Zap as references, fixing their known bugs, removing `_G`, targeting better CPU and bandwidth, with a wrapper on top that replaces Knit. He asked for a handoff file. `HANDOFF.md` was written with a bundled reference set.
7. Mike created the project folder `C:\Users\Michael\OneDrive\Desktop\Game Development\Volt\Documents`. The project is named **Volt**, one of the three name candidates offered. This bundle was copied there.

---

## 2. Facts established

**Kind: fact, verified against GitHub API and source on 2026-09-20**

| Item | Value |
|---|---|
| Zap latest | v0.6.29, released 2026-06-23, only 2026 release |
| Zap rewrite branch | last commit 2024-07-07, dormant |
| Zap maintainer | sasial-dev maintains 0.6.x; original author inactive |
| Zap license | MIT |
| Zap compiler language | Rust, shipped as native binaries plus WASM for the playground |
| Blink latest stable | v0.18.9, released 2026-09-19, bug-fix-only line since January 2026 |
| Blink latest pre-release | v1.0.0-pre.10, released 2026-09-19, tenth pre-release since 2026-01-14 |
| Blink maintainer | 1Axen, single author, 205 of roughly 232 contributions |
| Blink license | MIT |
| Blink compiler language | Luau, run under Lune (0.18) or Lute (1.0), packaged as a standalone executable |
| GitHub stars | Zap 187 / 29 forks; Blink 182 / 36 forks |
| Published benchmark | `benchmark/Benchmarks.md` in the Blink repo, run 2025-04-30, Blink v0.17.1 vs Zap v0.6.20 vs ByteNet v0.4.3, Ryzen 9 7900X |
| Benchmark Entities median FPS | Blink 42, Zap 39, ByteNet 32, Roblox 16 |
| Benchmark Booleans median FPS | Blink 97, Zap 52, ByteNet 35, Roblox 21 |
| Benchmark bandwidth | identical across the three buffer libraries; compression-dominated because the payload never changes |
| Earlier benchmark revision | 2024-05-06 run, Blink v0.11.1 vs Zap v0.6.3 |
| Independent comparison | Packet library thread, 2025-04-04, Zap 0.6.19 vs Blink 0.17.0: "blink is slightly better than zap" |
| Biggest expected mover on re-run | Zap bitpacking, v0.6.24 and v0.6.25 (July 2025), postdates the benchmark; Blink 1.0 has no bitpacking (#105 open) |

Full issue list with numbers is in `HANDOFF.md` section 6.

---

## 3. Recommendation given and why

**Kind: explanation, from the research report**

For a brand-new project starting September 2026, use Zap 0.6.29. Not because of docs, though Zap's docs are structurally better. Because Blink is mid-rewrite with two parallel lines: stable 0.18.9 is bug-fix-only and uses a syntax that will not carry into 1.0, while 1.0.0-pre.10 has no docs site, no working TypeScript output, and was fixing basic validation bugs in the week before the session. Zap 0.6.x is also frozen, but stably: declared feature complete September 2024, no forced migration coming, in production at studios running forks.

Zap's weakness is thin maintenance: one release in 2026, a memory-leak bug (#216) and a module-size bug (#225) without maintainer reply, a community fix PR (#223) closed unmerged.

Blink is the better choice for a Studio-only workflow (official plugin), for schemas needing 64-bit integers or generics, for a team that can patch Luau but not Rust, or if a re-run shows a CPU gap on the game's own payload shapes.

Mike's later decision to build his own package supersedes this recommendation for the Volt project. The recommendation remains the answer to the narrower question "which of the two should a new project adopt unmodified."

---

## 4. How buffer networking works, and why it is generated

**Kind: explanation**

### 4.1 The two wins

Roblox's `buffer` type is a raw byte array with calls like `buffer.writeu8`, `buffer.writef32`, `buffer.readu16` at a byte offset. Sending a buffer through a RemoteEvent costs roughly its length. Sending a Luau table costs a type tag per value plus every field name as a string, and one network call per fire.

The gains are bytes on the wire and CPU, not memory. Generated code can make memory worse; Zap #225 is a studio whose generated modules grew past Roblox bytecode limits.

### 4.2 The machine both libraries build

1. One outgoing buffer per side, plus a cursor. On the server, one buffer per player. Every `Fire` appends a one-byte event ID, then the fields in schema order at fixed widths: `u8` is 1 byte, `u16` is 2, `f32` is 4, `boolean` is 1, an enum is a 1-byte index, an array is a count prefix plus elements, an optional is a presence byte, a tagged enum is a tag byte then the variant's fields.
2. Once per frame on Heartbeat, everything written that frame is copied into a right-sized buffer and sent in a single RemoteEvent call. Unreliable events skip the batch and go straight out through an UnreliableRemoteEvent, capped at 1000 bytes.
3. The receiver walks the buffer: read the ID byte, branch to that event's reader, read each field at the promised width, build the Luau value, call listeners. Loop until the cursor reaches the end.
4. Instances cannot become bytes, so they ride in a side array passed as the RemoteEvent's second argument, and the reader pulls them out in order.

Zap differences at this level: it can inline resolved types, bit-packs booleans eight to a byte, and `manual_event_loop` lets you call the flush yourself.

### 4.3 Is an external compiler needed

Yes at build time, no at runtime. Both compilers run on the developer's machine once per schema change, like Rojo. Zap being Rust only matters if you want to patch Zap itself. Blink being Luau means Mike can patch it. Both emit plain Luau modules with zero runtime dependency on the compiler. Install is a prebuilt binary via Rokit or Aftman, or from GitHub Releases.

### 4.4 Why generate code instead of a runtime library

A runtime library like ByteNet builds serializers from a schema table when the game starts. Every write pays a lookup of "what type is this field" and a function call per field. Generated code is straight-line calls with constant sizes, and the whole schema is known so an event ID fits in one byte. The compiler also produces what a runtime library cannot: Luau type annotations and `.d.ts` for autocomplete, receive-side asserts from constraints like `u8(0..8)`, and a single source of truth so client and server cannot disagree on layout.

### 4.5 Worked Blink 0.18 example

Schema:

```
option ClientOutput = "src/client/Network.luau"
option ServerOutput = "src/server/Network.luau"

struct PlayerInput {
    Dir: u8(0..8),
    Jump: boolean,
    Look: f32,
}

event Input {
    From: Client,
    Type: Reliable,
    Call: SingleSync,
    Data: PlayerInput
}

event Damage {
    From: Server,
    Type: Reliable,
    Call: ManyAsync,
    Data: struct { TargetId: u16, Amount: u16 }
}
```

Client usage:

```lua
local Net = require(ReplicatedStorage.Client.Network)
RunService.PostSimulation:Connect(function()
    Net.Input.Fire({ Dir = 3, Jump = true, Look = 1.25 })
end)
Net.Damage.On(function(Data) print(Data.TargetId, Data.Amount) end)
```

Server usage:

```lua
local Net = require(ServerScriptService.Network)
Net.Input.On(function(Player, Data) end)   -- Data.Dir already checked 0..8
Net.Damage.FireAll({ TargetId = 17, Amount = 40 })
-- also Fire(Player, ...), FireList({...}, ...), FireExcept(Player, ...)
```

One `Input.Fire` produces seven bytes: `00` event ID, `03` Dir, `01` Jump, `00 00 A0 3F` Look as little-endian f32. Three fires in one frame become one 21-byte packet.

The real generated write and read functions, reconstructed from Blink's generator (assert text approximated):

```lua
SerdesFunctions.WriteEVENT_DATA_Input = function(Value: { Dir: number, Jump: boolean, Look: number })
	-- Allocate BLOCK: 7 bytes
	local BLOCK_START = Allocate(7)
	buffer.writeu8(SendBuffer, BLOCK_START + 0, 0)
	buffer.writeu8(SendBuffer, BLOCK_START + 1, Value.Dir)
	buffer.writeu8(SendBuffer, BLOCK_START + 2, Value.Jump and 1 or 0)
	buffer.writef32(SendBuffer, BLOCK_START + 3, Value.Look)
end

SerdesFunctions.ReadEVENT_DATA_Input = function(): { Dir: number, Jump: boolean, Look: number }
	-- Read BLOCK: 6 bytes
	local BLOCK_START = Read(6)
	local Value = {} :: any
	Value.Dir = buffer.readu8(RecieveBuffer, BLOCK_START + 0)
	assert(Value.Dir >= 0 and Value.Dir <= 8, "Dir out of range")
	Value.Jump = (buffer.readu8(RecieveBuffer, BLOCK_START + 1) == 1)
	Value.Look = buffer.readf32(RecieveBuffer, BLOCK_START + 2)
	return Value
end
```

The generated module around those functions: the buffer runtime from `Templates/Base.luau` (64-byte buffer growing 1.5x, `Allocate`, `Read`, `Save`, `Load`), remotes named `BLINK_RELIABLE_REMOTE` and `BLINK_UNRELIABLE_REMOTE` created by the server in ReplicatedStorage, `StepReplication` connected to `RunService.Heartbeat`, an `OnClientEvent` or `OnServerEvent` handler with `while RecieveCursor < Size do` and an `if Index == 0 then ... elseif` chain, and a frozen returns table of `Fire`, `FireAll`, `FireList`, `FireExcept`, `On`, `Iter` per event. `Fire` calls the write function; the dispatcher branch calls the read function then the listener. `SingleSync` calls the listener inline; if no listener is attached the arguments are queued up to 256 deep.

Files produced by one `blink` run: client module, server module, optional types file (`TypesOutput`), optional `.d.ts` pair (`Typescript = true`).

---

## 5. Assessment of building our own package

**Kind: explanation and decision input**

### 5.1 What is small

The runtime. Blink's three template files total about five kilobytes: a growing buffer with a cursor, a Heartbeat flush, a per-player send buffer on the server, and a dispatcher that reads an ID byte and branches. A clean version is a few hundred lines.

### 5.2 What is expensive

Everything the compiler produces around the runtime:

- Paired serializers: a write function on one side and a read function on the other, same field order and widths, both touched on every schema change.
- Receive-side validation: every range, string length, array count, enum index, buffer bound checked before game code sees the value. An exploiter controls every byte. A compiler emits these from the schema; by hand, forgetting one is easy and silent.
- Types: autocomplete and type errors come from generated annotations.
- Edge cases: Instances in a side array with nil handling, optionals, nested arrays, the 1000-byte unreliable cap, events fired before a listener exists, functions with invocation IDs and timeouts, PlayerRemoving cleanup, remote name collisions between two copies of a module.

Reference cost: Blink's generator is about 80 KB of Luau and took one author 91 releases over roughly 2.7 years.

### 5.3 Decision guide given

- Go fully custom (runtime plus hand-written packets) when packet count is modest (roughly under twenty), one person owns the networking layer, and a validator is written for every incoming packet on day one.
- Fork Blink when Blink's design is right but the syntax, output shape, or validation policy should bend to Mike's workflow. Adding a feature to a working compiler is days; writing one is months. A fork also sidesteps Blink's 1.0 uncertainty.
- Use Zap or Blink unmodified when shipping matters more than owning the transport. Delta compression, relevancy filtering, rate limiting, and packet caps can sit on top of either.

Both libraries already have a bus factor of one. A custom system has the same bus factor, but the one person is Mike and the codebase is one he understands. That costs ongoing time that competes with the game.

### 5.4 Recommended first version if custom

One shared runtime module for buffer and cursor management; one module per packet exposing `write`, `read`, `validate`; event ID as the first byte; reliable batching on Heartbeat, unreliables sent immediately; a hard cap on incoming buffer length and per-player fires per second before any decode; a test harness that round-trips every packet through write then read and asserts equality. Add a generator only when the same field is being edited in three places.

### 5.5 Mike's decision after this assessment

Build from scratch, with Blink and Zap as source references. Fork remains an explicit alternative that the next session must weigh. See `HANDOFF.md` sections 2 and 4.

---

## 6. How Blink 0.18 generates code

**Kind: explanation, verified from source in `reference/sources/blink-0.18/`**

Five stages, all Luau running outside Roblox under Lune:

1. **CLI** (`CLI/init.luau`): parses `blink.exe [CONFIG] [OPTIONS]`; options are `--watch`, `--quiet`, `--compact`, `--yes`, hidden `--ast` and `--stats`. Calls `Utility/Compile.luau`.
2. **Compile**: reads the file, parses to an AST, resolves output paths from `ClientOutput` and `ServerOutput`, calls the generator once for "Server" and once for "Client", optionally `GenerateShared` for a types file and `GenerateTypescript` for `.d.ts`, writes the files.
3. **Lexer** (`Lexer.luau`): a table of Lua string patterns tried in order at the cursor. Tokens carry type, value, start, end. Types include `Keyword`, `Primitive`, `Identifier`, `Range` for `(0..8)`, `Array` for `[..10]`, `Optional` for `?`, `Class` for `(Player)`, `Merge` for `..`, `Import`, `As`, and punctuation. Whitespace and comments are matched then skipped. Which word is a keyword or primitive comes from `Settings.luau`, which also holds each primitive's bounds (`u8` is 0 to 255, `f32` is plus or minus 16777216, and so on) and which attributes it allows. A `Highlighting` lexer mode keeps whitespace for the Studio plugin editor.
4. **Parser** (`Parser.luau`): recursive descent with one-token lookahead (`Peek`, `Consume`, `TryConsume`). Options first, then a declaration loop until end of file. Keywords route to `Type`, `Struct`, `Enum`, `TagEnum`, `Map`, `Set`, `Tuple`, `Event`, `Function`, `Namespace`, `Import`. Events are parsed by `Structure` against a fixed schema of allowed fields; `From`, `Type`, `Call` must hold permitted words, duplicates and missing fields error with spans. `Data` is parsed as a full type expression. Named type references are resolved and inlined into the referencing node. Ranges are validated against primitive bounds. Output: a `Body` node holding `Options` and `Declarations`.
5. **Generator** (`Generator/init.luau`, `Prefabs.luau`, `Blocks.luau`, `Util.luau`, `Typescript.luau`):
   - **Prefabs**: per-primitive `Read` and `Write` emitters, each appending one line. `u8` write is `buffer.writeu8(SendBuffer, <offset>, <value>)`. Boolean writes `Value and 1 or 0`. Color3 writes three u8. Vector writes three components at the chosen encoding. `f16` is hand-rolled bit manipulation because the buffer library has no half float. A wrapper adds validation lines: always on the read side, on the write side only when `WriteValidations` is on.
   - **Blocks**: a structured-code builder. `Compare` emits `if`, `Branch` emits `elseif` or `else`, `Loop` emits `for`, `While`, `Iterator`, `End` emits `end`; each returns the nested block so calls chain. `Allocate(n)` and `Read(n)` do not emit calls; they accumulate a byte count and return the string `BLOCK_START + <offset>`. On `End`, the block inserts `local BLOCK_START = Allocate(<total>)` or `Read(<total>)` at its top. One cursor bump per block, constant offsets per field. Inside an array loop of fixed-size elements it allocates `<element size> * Length` once before the loop. This is the core of Blink's CPU edge.
   - **Recursion**: `Generators.UserType` dispatches on node type to `Declarations.Primitive`, `Struct`, `Array`, `Optional`, `Enum`, `TagEnum`, `Map`, `Set`, `Tuple`, passing the same read block and write block. Struct iterates fields with the variable extended to `Value.Field`. Array emits a length prefix (sized by the upper bound), opens a loop on both blocks, recurses on the element type. Optional writes a presence byte and wraps in an `if`; for Instances it checks the side array instead. TagEnum writes a tag byte and branches per variant. Read and write are built by the same walk, so they cannot disagree.
   - **Per event**: `Generators.Event` wraps the walk in a function pair stored in `SerdesFunctions`, writing the event's index byte first. Functions add an invocation ID byte and, on return, a success byte. `Declarations.Event` emits `Fire`, `FireAll`, `FireList`, `FireExcept` on the server (reliable writes go into each player's saved buffer via `Load` and `Save`; unreliable writes are copied and fired immediately) and `Fire` on the client, plus `On` with a disconnect closure, or `Iter` and `Next` for polling. Method names come from the `Casing` option via one lookup table.
   - **Assembly** (`Generator.Generate`): concatenates directives and version header, the `_G._BLINK` scope guard, the top half of the side template (services), Future or Promise requires, `local SerdesFunctions = {}`, `BASE_EVENT_NAME`, the base runtime, sync-validation locals, queue declarations, Luau `export type` lines, the no-op branch for Studio edit mode, the bottom half of the side template (remotes, `StepReplication`), `RunService.Heartbeat:Connect(StepReplication)` unless `ManualReplication`, the two `OnClientEvent` or `OnServerEvent` connections (`while RecieveCursor < Size do` plus the `if`/`elseif` chain), and the frozen `Returns` table.

Templates are three Luau strings. `Base.luau` is the buffer runtime. `Client.luau` and `Server.luau` each contain a `-- SPLIT --` marker separating service lookups from remote setup and `StepReplication`.

The compiler runs with `--!native` and `--!optimize 2`, which affects compile speed only. A release build strips per-field comments from the output.

### Blink 1.0 rewrite pipeline

From `reference/sources/blink-1.0-rewrite/`: lexer, parser, AST, HIR with analysis passes (dereferencing, flattening, instantiation, type checking), LIR with builders per Luau library (`buffer`, `bit32`, `math`, `string`, `table`, `task`, `vector`, `coroutine`, `debug`, roblox) and per type (`ty/luau/*`, `ty/roblox/*`), an optimizer, then codegen templates (`append_headers`, `append_services`, `append_client`, `append_server`, `append_buffer_fns`). Much larger than 0.18. Runs under Lute.

### Zap 0.6 output

From `reference/sources/zap-0.6.x/`: emitted from Rust in `zap/src/output/luau/{client,server,mod,types}.rs` with `base.luau` as the runtime template, plus `typescript/*.rs` for `.d.ts` and `tooling.rs` for the packet-inspector deserializer. Same overall output shape as Blink.

---

## 7. The `_G` finding

**Kind: fact and preference**

Mike does not use `_G` in any runtime code and objected to it appearing in generated output.

**Blink 0.18.9** emits these lines unconditionally near the top of both client and server modules, built at `Generator/init.luau` around line 1277 as `ScopeValidationBody`:

```lua
_G._BLINK = _G._BLINK or {}
if _G._BLINK["BLINK"] then
	error("[Blink]: An instance of blink is already running with the remote scope \"BLINK\". Change the remote scope of either instance to avoid conflicts.")
end
_G._BLINK["BLINK"] = true
```

**Zap 0.6.29** emits the equivalent unconditionally on both sides via `push_remote_scope_validation` in `zap/src/output/luau/mod.rs`, keyed by `remote_folder` and `remote_scope`, storing the version string:

```lua
if not _G.__ZAP then
	_G.__ZAP = { ["ZAP"] = {} }
elseif not _G.__ZAP["ZAP"] then
	_G.__ZAP["ZAP"] = {}
elseif _G.__ZAP["ZAP"]["ZAP"] ~= nil then
	error(`There is already an instance of Zap with the same remote_scope ...`)
end
_G.__ZAP["ZAP"]["ZAP"] = "0.6.29"
```

Zap also reads roblox-ts's Promise from `_G[script]` when `typescript = true` and `yield_type = "promise"`, which is roblox-ts's convention.

**Purpose**: a require-time duplicate guard. It catches two different generated modules loading in one VM with the same scope, which would bind both to the same `BLINK_RELIABLE_REMOTE` and decode each other's packets against the wrong index table. A generated file cannot require a shared registry it does not know exists, so `_G` is the only per-VM table reachable without an instance dependency. No packet path touches it.

**Blink 1.0** has no `_G` in generated output at all. Its remote setup is `FindFirstChild` then `Instance.new` with no conflict check. The guard was judged optional by its own author.

**Options given**: set a unique `RemoteScope` per generated module regardless (the real fix); remove the block in a fork (five-line change); post-process the output. An instance-attribute guard is possible but not worth it. **Decision for Volt: no `_G`, unique remote scope per module.**

---

## 8. Preferences and working style learned

**Kind: user preference**

- Does not use `_G` in runtime code.
- Prefers clear, complete documentation; this is why he initially leaned Zap.
- Leans toward Blink's approach and architecture.
- Wants to own and maintain his networking layer, customized to his style and workflow.
- Wants a wrapper on top of the transport that replaces Knit, so the transport API must be small and regular.
- Wants the package lightweight and simple.
- Understands the Heartbeat-batched buffer model and read Blink's generator; explanations can assume that level.
- Typed "Zip" for Zap in one message; the intended library is Zap.
- Chose the name **Volt** for the project.

---

## 9. Goals for Volt, in Mike's words

**Kind: requirement**

Increase runtime performance over Blink and Zap; lightweight codebase; simple, easy-to-understand usage so a wrapper can replace Knit; use-case coverage and fixes for what Blink and Zap miss; known bug fixes; decreased CPU and bandwidth; buffers, packets, Heartbeat; security and validation for bytes; no `_G`; an improved lightweight simple package system (read as minimal runtime, minimal generated code, simple install; to confirm).

---

## 10. Open questions

**Kind: open question**

- From scratch versus fork of Blink: Mike leans from scratch; the next session must recommend with conditions.
- Meaning of "lightweight simple package system": confirm the reading above.
- Name: Volt is the folder name; verify no collision on Wally, pesde, DevForum, GitHub. Alternates offered were Pulse and Relay.
- Compiler host: Lune or Lute.
- Whether server-to-client functions, two-way events, delta compression, relevancy filtering, and unreliable fragmentation belong in the transport or the wrapper.
- Benchmark tooling on this machine: Roblox Studio, rojo, darklua, run-in-roblox availability not yet checked.

---

## 11. Source URLs used

- https://github.com/red-blox/zap and https://zap.redblox.dev
- https://github.com/1Axen/blink and https://1axen.github.io/blink/
- https://github.com/1Axen/blink/blob/main/benchmark/Benchmarks.md
- https://github.com/1Axen/blink/tree/main/src (0.18 compiler)
- https://github.com/1Axen/blink/tree/rewrite (1.0 compiler)
- https://github.com/red-blox/zap/tree/0.6.x/zap/src/output (Zap emitters)
- DevForum Blink thread: https://devforum.roblox.com/t/2959671
- Issue numbers cited in `HANDOFF.md` section 6 refer to the respective GitHub repos.
