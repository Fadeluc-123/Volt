---
type: decision
date: 2026-09-20
session: 14e4b904
status: active
description: Volt's runtime and generated output contain no _G; duplicate-instance safety comes from a unique remote scope per generated module instead.
tags: [volt, runtime, codegen]
---
# No `_G` anywhere in Volt; unique remote scope per generated module
Up: [[Decisions]]

**Decision:** Volt emits no `_G` in generated output and uses none in its runtime. The problem Zap 0.6 and Blink 0.18 solve with a `_G` duplicate-instance guard is solved by giving every generated module a unique remote scope, so two generated modules in one VM can never bind the same remotes.

**Alternatives:** keep the `_G` guard (rejected: Mike's workspace-wide `_G` ban, [[Standards/code-style-formatting]] 6.7); an Instance-attribute guard on the remote folder (possible, judged not worth it); post-process the output to strip the block (a workaround, not a design).

**Revisit when:** never for `_G`. The remote-scope mechanism may be revisited if a schema-hash handshake ([[Research/networking-use-case-coverage-list]]) makes a separate guard redundant.

**Consequences:** Remote naming and scope are part of the IDL options from day one; the design document specifies how scope uniqueness is guaranteed and what happens when two modules do collide.
Related: [[Research/global-guard-in-generated-code]] [[Decisions/volt-goals]]
