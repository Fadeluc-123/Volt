---
type: research
date: 2026-09-20
session: 14e4b904
description: The assessment given to Mike on building his own package: the runtime is small, the compiler is the expensive part, when full-custom, fork or unmodified wins, and the recommended first version if custom.
sources: ["KB/Library/session-context-2026-09-20.md", "KB/Library/handoff-2026-09-20.md"]
tags: [volt, architecture, planning]
---
# Building our own package: what is small, what is expensive, and when a fork wins
Up: [[Research]]

**Question:** Is building a custom buffer-networking package a good idea, and what does it cost?

**Answer:**
- **What is small: the runtime.** Blink's three template files total about five kilobytes: a growing buffer with a cursor, a Heartbeat flush, a per-player send buffer on the server, and a dispatcher that reads an ID byte and branches. A clean version is a few hundred lines.
- **What is expensive: everything the compiler produces around the runtime.** Paired serializers (a write function on one side and a read function on the other, same order and widths, both touched on every schema change); receive-side validation (every range, string length, array count, enum index and buffer bound checked before game code sees the value, because an exploiter controls every byte, and forgetting one by hand is easy and silent); types (autocomplete and type errors come from generated annotations); and edge cases (Instances in a side array with nil handling, optionals, nested arrays, the 1000-byte unreliable cap, events fired before a listener exists, functions with invocation IDs and timeouts, PlayerRemoving cleanup, remote name collisions between two copies of a module). Reference cost: Blink's generator is about 80 KB of Luau and took one author 91 releases over about 2.7 years; Zap's Rust compiler is larger still. A from-scratch generator that reaches feature parity is months, not weeks. **A from-scratch generator scoped to what this project needs, with a coverage matrix keeping it honest, is the realistic path.**
- **Decision guide:**
  - **Fully custom (runtime plus hand-written packets)** when packet count is modest (roughly under twenty), one person owns the networking layer, and a validator is written for every incoming packet on day one.
  - **Fork Blink** when Blink's design is right but the syntax, output shape or validation policy should bend to Mike's workflow. Adding a feature to a working compiler is days; writing one is months. A fork also sidesteps Blink's 1.0 uncertainty and keeps the Studio plugin and VS Code extension.
  - **From scratch** when we want a different IDL surface or generated API shape and the changes touch parser, block builder and templates at once; when validation, packet caps, rate limiting and decode-failure policy should be designed into the runtime from day one; when we want a smaller generator than Blink 0.18's or 1.0's; and when we want to avoid inheriting Blink's two-track syntax split and open 1.0 bugs.
  - **Zap or Blink unmodified** when shipping matters more than owning the transport. Delta compression, relevancy filtering, rate limiting and packet caps can sit on top of either.
- Both libraries already have a bus factor of one. A custom system has the same bus factor, but the one person is Mike and the codebase is one he understands. That costs ongoing time that competes with the game.
- **Recommended first version if custom:** one shared runtime module for buffer and cursor management; one module per packet exposing `write`, `read`, `validate`; event ID as the first byte; reliable batching on Heartbeat, unreliables sent immediately; a hard cap on incoming buffer length and per-player fires per second before any decode; a test harness that round-trips every packet through write then read and asserts equality. Add a generator only when the same field is being edited in three places.

**Sources:** consolidated in [[Library/session-context-2026-09-20]] section 5 and [[Library/handoff-2026-09-20]] section 4.
**Confidence:** high on the cost analysis (read from source sizes and release history); the decision guide is judgement, recorded so the next session argues from it rather than redoing it.
**Applies to:** the from-scratch versus fork recommendation in [[Planning/volt-next-session-deliverables]].
Related: [[Decisions/build-from-scratch-not-fork]] [[Research/blink-0-18-compiler-pipeline]] [[Research/how-buffer-networking-works]]
