---
type: path
description: One node per decision Mike has made about Volt, with the alternatives and the conditions for revisiting it. Read in full at every session start.
---
# Decisions
Up: [[Core]]

One node per decision. A decision is a ruling by Mike that constrains how Volt is built: what it is, what it is not, which approach was chosen and which were set aside. It is recorded so no session re-litigates it by accident, and so the conditions under which it should be reopened are explicit.

**Read at session start:** always, in full (injected by the SessionStart hook).

## When to add or update

When Mike rules on something, in the turn it happens. If a decision is later changed, edit the node: set `status: superseded`, say what replaced it and link the new node. Do not delete decision nodes; the history of what was decided and why is part of the record. Research findings that merely *recommend* something are not decisions; they live in Research until Mike rules.

## Node template

File name: a short kebab-case slug that names the decision, for example `build-from-scratch-not-fork.md`.

```md
---
type: decision
date: YYYY-MM-DD
session: <first 8 chars of session id>
status: active
description: <one line: the decision>
tags: []
---
# <Decision, one line>
Up: [[Decisions]]

**Decision:** what was decided, stated so it can be applied without interpretation.
**Alternatives:** what else was on the table and why it lost.
**Revisit when:** the conditions under which this is reopened. "Never" is a valid answer.
**Consequences:** what it constrains in the design or the work.
Related: [[Research/...]] [[Planning/...]] [[Standards/...]]
```

`status` is one of `active`, `superseded`, `pending` (Mike leans one way but has not ruled).

## Nodes
<!-- kb:auto-start -->
- [[Decisions/build-from-scratch-not-fork|Build Volt from scratch, with a Blink fork as the explicit alternative]] - Volt is built from scratch with Blink and Zap as source references; a fork of Blink stays an explicit alternative the next session must weigh and recommend on.
- [[Decisions/bytenet-out-of-scope|ByteNet is out of scope]] - ByteNet is excluded from the Zap versus Blink comparison and stays out of scope for Volt's references and benchmarks.
- [[Decisions/compiler-in-luau-output-plain-luau|The compiler is Luau; the output is plain Luau with no runtime dependency]] - Volt's compiler is written in Luau and runs outside Roblox under Lune or Lute; its output is plain Luau with zero runtime dependency on the compiler.
- [[Decisions/design-doc-before-code|No package code before the design document is reviewed]] - No package code is written before the design document is reviewed by Mike, and nothing under Reference/ is modified.
- [[Decisions/no-global-state-unique-remote-scope|No `_G` anywhere in Volt; unique remote scope per generated module]] - Volt's runtime and generated output contain no _G; duplicate-instance safety comes from a unique remote scope per generated module instead.
- [[Decisions/project-name-volt|The project is named Volt]] - The project is named Volt, chosen from the candidates Volt, Pulse and Relay; collision checks on Wally, pesde, DevForum and GitHub are still owed.
- [[Decisions/volt-goals|Volt's goals, in Mike's words and order]] - The goals for Volt in Mike's words and order, from faster runtime to a lightweight package with no _G, plus the wrapper that replaces Knit.
<!-- kb:auto-end -->
