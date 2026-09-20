---
type: research
date: 2026-09-20
session: 14e4b904
description: The research report's answer to "which of Zap or Blink should a new project adopt unmodified in September 2026" (Zap 0.6.29), why, and the conditions that flip it; superseded for Volt by the build-from-scratch decision.
sources: ["KB/Library/zap-vs-blink-report.md"]
tags: [zap, blink, recommendation]
---
# Zap vs Blink: the recommendation for unmodified adoption
Up: [[Research]]

**Question:** Which of Zap or Blink should a brand-new Roblox project adopt unmodified, starting September 2026?

**Answer:** **Zap 0.6.29**, and revisit the day Blink 1.0 ships stable with docs. Not because of docs, though Zap's are structurally better; because Blink is mid-rewrite. Blink's stable line (0.18.9) is bug-fix only on a syntax that will not carry into 1.0, and the rewrite (1.0.0-pre.10) has no docs site, no working TypeScript output, and was fixing basic correctness bugs (ranges not enforced, a validation error corrupting the outgoing buffer) the week before the report. Zap 0.6.x is also frozen, but stably: feature complete since September 2024, no forced migration coming, in production at studios running forks. The real choice is between two frozen APIs with opposite failure modes: Zap frozen by neglect but stable in practice; Blink frozen by design while its successor is built in public. For a new project the first kind is cheaper, and the migration cost between the two IDLs is modest for a small schema, so the decision is reversible early.

Zap's weakness is thin maintenance (one 2026 release, #216 and #225 unanswered, PR #223 closed unmerged) and a Rust compiler a Luau team cannot easily patch.

**Blink is the better choice when:** the workflow is Studio-only (official plugin); the schema needs types Zap lacks (64-bit ints, `f16`, generics, two-way events); the team expects to patch its networking compiler and can patch Luau but not Rust; a re-run shows a CPU gap on the game's own payload shapes at rates the game reaches; or Blink 1.0 reaches a stable, documented release before the first event is written.

**Shared risks regardless of pick:** oversized-buffer DoS (Zap #219, Blink #45), undefined behaviour when a sync callback yields, 1000-byte unreliable cap, deserialization error on a nil non-optional Instance. Put a per-player packet-size and rate guard at the RemoteEvent boundary on day one.

**Status for Volt:** Mike set this recommendation aside on 2026-09-20 and decided to build his own package ([[Decisions/build-from-scratch-not-fork]]). It remains the answer to the narrower question above.

**Sources:** the full report with a URL per claim, [[Library/zap-vs-blink-report]] (2026-09-20).
**Confidence:** high as a synthesis of the four research notes; the benchmark-driven parts carry the caveats in [[Research/blink-published-benchmark-and-changes-since]].
**Applies to:** the from-scratch versus fork recommendation, and any future question of adopting a third-party library for a Whiteoak game.
Related: [[Research/zap-0-6-current-state]] [[Research/blink-current-state]] [[Research/zap-blink-community-and-ecosystem]] [[Decisions/bytenet-out-of-scope]]
