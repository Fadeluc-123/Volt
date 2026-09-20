---
type: research
date: 2026-09-20
session: 14e4b904
description: Both Zap 0.6 and Blink 0.18 emit a _G duplicate-instance guard at require time; what it does, why it exists, that Blink 1.0 dropped it, and the options for avoiding it.
sources: ["Reference/sources/blink-0.18/gen/init.luau", "Reference/sources/zap-0.6.x/luau_mod.rs", "KB/Library/session-context-2026-09-20.md"]
tags: [zap, blink, codegen, runtime]
---
# The `_G` duplicate-instance guard in Zap and Blink generated code
Up: [[Research]]

**Question:** Is `_G` used at runtime in generated networking code, and what for?

**Answer:** Yes, in both, once at require time; no packet path touches it.
- **Blink 0.18.9** emits unconditionally near the top of both modules (built in `Generator/init.luau` around line 1277 as `ScopeValidationBody`):
  ```lua
  _G._BLINK = _G._BLINK or {}
  if _G._BLINK["BLINK"] then
  	error("[Blink]: An instance of blink is already running with the remote scope \"BLINK\". Change the remote scope of either instance to avoid conflicts.")
  end
  _G._BLINK["BLINK"] = true
  ```
- **Zap 0.6.29** emits the equivalent on both sides via `push_remote_scope_validation` in `zap/src/output/luau/mod.rs`, keyed by `remote_folder` and `remote_scope`, storing the version string in `_G.__ZAP[scope][scope]`. Zap also reads roblox-ts's Promise from `_G[script]` when `typescript = true` and `yield_type = "promise"` (roblox-ts's own convention).
- **Purpose:** a require-time duplicate guard. Two different generated modules loading in one VM with the same scope would bind the same `BLINK_RELIABLE_REMOTE` and decode each other's packets against the wrong index table. A generated file cannot require a shared registry it does not know exists, so `_G` is the only per-VM table reachable without an instance dependency.
- **Blink 1.0** has no `_G` in generated output at all. Its remote setup is `FindFirstChild` then `Instance.new` with no conflict check; the guard was judged optional by its own author.
- **Options:** set a unique `RemoteScope` per generated module regardless (the real fix); remove the block in a fork (five-line change); post-process the output. An Instance-attribute guard is possible but not worth it.

**Sources:** read from the source snapshots; consolidated in [[Library/session-context-2026-09-20]] section 7.
**Confidence:** high.
**Applies to:** [[Decisions/no-global-state-unique-remote-scope]]; the remote-scope option in Volt's IDL.
Related: [[Research/how-buffer-networking-works]] [[Standards/code-style-formatting]]
