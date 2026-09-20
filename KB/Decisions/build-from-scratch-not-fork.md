---
type: decision
date: 2026-09-20
session: 14e4b904
status: active
description: Volt is built from scratch with Blink and Zap as source references; a fork of Blink stays an explicit alternative the next session must weigh and recommend on.
tags: [volt, architecture, scope]
---
# Build Volt from scratch, with a Blink fork as the explicit alternative
Up: [[Decisions]]

**Decision:** Mike's working decision (2026-09-20): build our own buffer-networking package completely from scratch. Use Blink and Zap as source references for what each does well. Fix every known issue and bug in both. Improve runtime performance. Remove `_G`. Keep the package lightweight and simple. This is recorded as the working decision, not a final one: the next session must deliver a from-scratch versus fork recommendation with the conditions under which the fork wins, and Mike decides.

**Alternatives:**
- **Fork Blink 0.18.9.** Wins when time to a working, tested compiler matters more than owning every line; when the wanted changes are additive (drop the `_G` guard, add packet caps and bitpacking, fix listed bugs, change casing or output layout); and when the Studio plugin and VS Code extension are wanted without rebuilding them. Blink is one author, 91 releases over about 2.7 years; a from-scratch generator that reaches feature parity is months, not weeks.
- **Adopt Zap or Blink unmodified.** The research report's answer for a plain new project was Zap 0.6.29 ([[Research/zap-vs-blink-recommendation]]). Mike set it aside because he dislikes `_G` in both, Blink is mid-rewrite, and Zap's Rust compiler is not something he can patch.

**Revisit when:** the next session's recommendation is delivered ([[Planning/volt-next-session-deliverables]]); or if the scoped from-scratch generator is projected at months without a coverage matrix keeping it honest.

**Consequences:** The compiler is Luau ([[Decisions/compiler-in-luau-output-plain-luau]]); no `_G` ([[Decisions/no-global-state-unique-remote-scope]]); the known-bug list is a requirements list ([[Research/known-bugs-in-zap-and-blink]]); nothing is written before the design document is reviewed ([[Decisions/design-doc-before-code]]).
Related: [[Research/build-vs-fork-assessment]] [[Decisions/volt-goals]] [[Library/handoff-2026-09-20]]
