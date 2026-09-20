---
type: plan
date: 2026-09-20
session: 14e4b904
status: active
description: The ordered deliverables for the next working session on Volt, from the final research pass to name verification, with the research gaps and open questions to close.
tags: [volt, roadmap]
---
# Volt: next working session deliverables
Up: [[Planning]]

**Goal:** Mike has everything he needs to approve a design for Volt: a from-scratch versus fork recommendation, a coverage matrix, a design document, a benchmark plan and a verified name. No package code is written before the design document is reviewed ([[Decisions/design-doc-before-code]]).

**Steps:** in order.
- [ ] **Final research pass** for building our own package on the strengths of both libraries. Inputs: [[Research/strengths-to-borrow-from-zap-and-blink]], [[Research/known-bugs-in-zap-and-blink]], [[Research/networking-use-case-coverage-list]], [[Research/blink-0-18-compiler-pipeline]]. Close the gaps below.
- [ ] **Recommendation with reasoning: from scratch versus fork of Blink.** Mike leans from scratch ([[Decisions/build-from-scratch-not-fork]]). State the conditions under which the fork wins ([[Research/build-vs-fork-assessment]]) and let him decide.
- [ ] **Use-case coverage matrix**: every row of [[Research/networking-use-case-coverage-list]] marked covered, partial or missing for Blink 0.18, Blink 1.0-pre, Zap 0.6, and planned for Volt. Nothing either library supports is silently dropped, and the cases neither supports are included.
- [ ] **Design document**: IDL syntax, generated runtime shape, generator architecture, package layout, install story, validation and security policy, and the wrapper surface a Knit replacement will sit on. Every decision cites which library it borrows from or says it is new and why. Follows [[Standards/code-style-overview]] for any code shown.
- [ ] **Benchmark plan and harness**: [[Planning/volt-benchmark-plan]].
- [ ] **Name verification**: check Volt (and the fallbacks Pulse and Relay) against Wally, pesde, the DevForum and GitHub for existing Roblox libraries ([[Decisions/project-name-volt]]). Offer alternates if any collide.

**Research gaps to close:**
- Zap's `rewrite` branch was not read; confirm it is dead and whether any design idea in it is worth borrowing.
- Exact type coverage of Zap's bitpacking (PR #198) is not established.
- Blink 1.0 profile semantics and `release` optimisations were seen only in release notes, not source; the snapshot in `Reference/sources/blink-1.0-rewrite/` can answer this.
- Whether Blink's VS Code extension targets 1.0 syntax is unknown.
- No official Zap DevForum thread exists; discussion lives in the Roblox OSS Discord, which was not accessible.

**Open questions for Mike:**
- Meaning of "an improved lightweight simple package system" ([[Decisions/volt-goals]] goal 10); confirm the reading.
- Compiler host: Lune or Lute ([[Decisions/compiler-in-luau-output-plain-luau]]).
- Whether server-to-client functions, two-way events, delta compression, relevancy filtering and unreliable fragmentation belong in the transport or the wrapper.
- Benchmark tooling on this machine: Roblox Studio, rojo, darklua, run-in-roblox availability not yet checked. Aftman is installed.

**Dependencies and risks:** the design document depends on the coverage matrix and the recommendation; the benchmark harness can proceed in parallel. Risk: a from-scratch generator scoped by ambition instead of by the matrix grows to months.
**Progress notes:**
- 2026-09-20: plan created from the handoff bundle; nothing started.
Related: [[Library/handoff-2026-09-20]] [[Decisions/build-from-scratch-not-fork]] [[Decisions/volt-goals]]
