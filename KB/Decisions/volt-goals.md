---
type: decision
date: 2026-09-20
session: 14e4b904
status: active
description: The goals for Volt in Mike's words and order, from faster runtime to a lightweight package with no _G, plus the wrapper that replaces Knit.
tags: [volt, requirements, scope]
---
# Volt's goals, in Mike's words and order
Up: [[Decisions]]

**Decision:** Volt exists to deliver these, in this order:

1. Increase runtime performance over Blink and Zap.
2. Lightweight codebase.
3. Simple, easy-to-understand usage, so that a wrapper system can be built on top that replaces Knit. The transport API must therefore be small and regular.
4. Use-case coverage and fixes for what Blink and Zap miss or leave incomplete.
5. Known bug fixes for everything in [[Research/known-bugs-in-zap-and-blink]].
6. Decreased CPU usage and decreased bandwidth usage.
7. Buffers, packets, Heartbeat batching.
8. Security and validation for every byte the server reads.
9. No `_G`. Mike does not use `_G` anywhere in his runtime code.
10. An improved, lightweight, simple package system. Read as: minimal runtime, minimal generated code, and a simple install and distribution story. **Confirm this reading with Mike if a design decision hinges on it.**

**Alternatives:** none; these are requirements, not a choice among options.

**Revisit when:** Mike restates or reorders them. Goal 10's reading is unconfirmed and is an open question in [[Planning/volt-next-session-deliverables]].

**Consequences:** Every design decision in the design document cites which goal it serves and which library (Blink, Zap, or new) it borrows from. The wrapper surface for a Knit replacement is part of the design, not an afterthought; the Knit conventions in [[Standards/code-style-knit-service-layout]] and [[Standards/code-style-client-server-communication]] describe what that wrapper must make easy.
Related: [[Decisions/build-from-scratch-not-fork]] [[Standards/working-with-mike]] [[Library/session-context-2026-09-20]]
