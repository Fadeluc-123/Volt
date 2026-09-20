---
type: decision
date: 2026-09-20
session: 14e4b904
status: active
description: Volt's compiler is written in Luau and runs outside Roblox under Lune or Lute; its output is plain Luau with zero runtime dependency on the compiler.
tags: [volt, compiler, tooling]
---
# The compiler is Luau; the output is plain Luau with no runtime dependency
Up: [[Decisions]]

**Decision:** If Volt is built from scratch, its compiler is written in Luau and run outside Roblox under Lune (as Blink 0.18 does) or Lute (as Blink 1.0 does). The generated modules are plain Luau with zero runtime dependency on the compiler. Mike must be able to patch the compiler without a Rust toolchain.

**Alternatives:** Rust, as Zap does (rejected: Mike cannot easily patch it, which is one of the reasons he set Zap aside).

**Revisit when:** the compiler host is chosen; Lune versus Lute is still open ([[Planning/volt-next-session-deliverables]]).

**Consequences:** The install story is a prebuilt binary (Rokit, Aftman, GitHub Releases) or a Lune/Lute script; the compiler codebase follows the code style in [[Standards/code-style-overview]]; the reference sources for the compiler design are Blink's ([[Research/reference-source-snapshots]]).
Related: [[Decisions/build-from-scratch-not-fork]] [[Research/blink-0-18-compiler-pipeline]]
