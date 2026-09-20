---
type: research
date: 2026-09-20
session: 14e4b904
description: The union of networking use cases across Zap 0.6, Blink 0.18 and Blink 1.0 plus the cases neither supports; the starting list the coverage matrix is built from.
sources: ["KB/Library/handoff-2026-09-20.md"]
tags: [networking, requirements, coverage]
---
# Networking use-case coverage list (input to the coverage matrix)
Up: [[Research]]

**Question:** What must the coverage matrix enumerate so nothing Blink or Zap supports is silently dropped, and the gaps in both are visible?

**Answer:** Start from the union of both libraries, then add the cases neither handles. Each becomes a matrix row marked covered, partial or missing for Blink 0.18, Blink 1.0-pre, Zap 0.6, and planned for Volt.

- **Types:** u8, u16, u32, i8, i16, i32, f32, f64; f16 (Blink 0.18 only); u24, u48, int64 or `integer` (Blink 1.0 only; Zap #67 open); booleans with bitpacking (Zap only); strings with length bounds, `string.utf8` and `string.binary` (Zap 0.6.24); buffers with length bounds; vectors with component encodings; CFrame with positional and rotational encodings, `AlignedCFrame` (Zap only); Color3, BrickColor, DateTime, DateTimeMillis; Instance with class constraint, `StreamedInstance` (Blink 1.0); Roblox `Enum` (Blink 1.0); `unknown`; structs with spread or merge; unit enums and tagged enums; real unions and literal types (Blink 1.0, Zap OR types); maps and sets with size bounds; arrays with size bounds; optionals; tuples and type packs; generics (Blink); recursive types.
- **Events:** client to server, server to client, two-way (Blink 1.0 `from: Both`); reliable and unreliable; ordered unreliable (Zap); call modes SingleSync, SingleAsync, ManySync, ManyAsync, Polling; `Fire`, `FireAll`, `FireList`, `FireExcept`, `FireSet` (Zap); named multi-parameter data; events fired before a listener exists (queue semantics and cap); disconnect handles.
- **Functions:** client to server with return; server to client functions (neither supports; decide); yield modes Coroutine, Future, Promise; tuple returns; invocation IDs, ring size and timeouts; error propagation to the caller.
- **Organisation:** namespaces or scopes; multi-file imports; `export` standalone serializers; casing options; remote scope naming; separate types output; TypeScript `.d.ts` output for roblox-ts.
- **Runtime and operations:** Heartbeat batching with `manual_event_loop`; per-player server buffers; Instance side-channel; packet size caps and per-player rate limiting; decode-failure policy and kick hook; schema hash handshake so mismatched client and server builds fail loudly; Studio edit-mode require; microprofiler labels; packet inspector deserializer; large-schema output sharding; mock transport for unit tests outside Roblox; hot reload in Studio; middleware or hook points for a framework wrapper (before-send, after-receive, per-event); memory cleanup on `PlayerRemoving`.
- **Wrapper surface for a Knit replacement:** the generated API must be small and regular enough that a service and controller layer can register events and functions by name, attach middleware, and expose typed handles. Decide whether that layer lives in the generated output or in a separate runtime module.
- **Missing in both today, decide where they belong (transport or wrapper):** delta compression or dirty-flag replication; interest or relevancy filtering per player; snapshot interpolation helpers; unreliable fragmentation above 1000 bytes.

**Sources:** [[Library/handoff-2026-09-20]] section 7, drawn from the docs and release notes of both libraries.
**Confidence:** high as a list of what exists; completeness is the matrix's job to prove.
**Applies to:** deliverable 3 in [[Planning/volt-next-session-deliverables]]; the wrapper design ([[Decisions/volt-goals]] goal 3).
Related: [[Research/strengths-to-borrow-from-zap-and-blink]] [[Research/known-bugs-in-zap-and-blink]] [[Standards/code-style-client-server-communication]]
