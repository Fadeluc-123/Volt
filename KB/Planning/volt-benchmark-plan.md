---
type: plan
date: 2026-09-20
session: 14e4b904
status: draft
description: How to benchmark Blink, Zap and Volt fairly, building on Blink's published harness and adding the scenarios, measurements and fairness controls it lacks.
tags: [volt, benchmark, performance]
---
# Volt benchmark plan
Up: [[Planning]]

**Goal:** A reproducible harness that compares Blink 0.18.9, Blink 1.0.0-pre.10, Zap 0.6.29 and Volt on CPU, bytes per packet and memory, on payloads shaped like real game traffic, so the performance goal in [[Decisions/volt-goals]] is measured rather than asserted.

**Steps:**
- [ ] Fetch Blink's `benchmark/` folder fresh from GitHub (not in the bundle): `Benchmarks.md`, `definitions/Definition.{blink,zap}`, `src/client/init.client.luau`, `src/server/init.server.luau`, `src/shared/benches/{Entities,Booleans}.luau`, `src/shared/modes/*.luau`, `build.bat`, `download.luau`, `generate.luau`, `run.luau`. Requires Roblox Studio, rojo, darklua, run-in-roblox; check which are installed.
- [ ] Pin versions by hand; `download.luau` pulls `releases/latest`. Targets: Zap v0.6.29, Blink v0.18.9, Blink v1.0.0-pre.10 with `Definition.blink` ported to 1.0 syntax and a `release` profile, harness adapters updated for `blink.exports.<event>.fire`.
- [ ] Reproduce the two published scenarios first (Entities: 100 six-u8 structs; Booleans: 1000 `true`) and compare against the 2025-04-30 numbers in [[Research/blink-published-benchmark-and-changes-since]].
- [ ] Run Zap twice: `write_checks = true` (default) and `write_checks = false`, because Blink's write validation defaults off.
- [ ] Add a third mode for Volt in `src/shared/modes/` once Volt exists.
- [ ] Measure bytes per packet with `buffer.len` on the flushed buffer, not `Stats.DataSendKbps`.
- [ ] Add isolated serialize and deserialize timings with `os.clock` loops, separate from the FPS test.
- [ ] Add realistic scenarios: strings, CFrames, optionals, nested structs, tagged enums, server broadcast to many players, many small events per frame, unreliable events, and a validation-cost scenario with malformed packets rejected.
- [ ] Randomise payloads per fire in at least one scenario so bandwidth numbers mean something.
- [ ] Measure memory: module bytecode size and steady-state heap.
- [ ] Record the Roblox Studio version; the 2025 run did not.
- [ ] Keep `include_profile_labels` off in comparison runs; use it only for diagnosis.
- [ ] Verify Zap's bitpacking by inspecting the `Booleans` writer in its generated `Client.luau` before trusting any FPS delta.

**Dependencies and risks:** tooling availability on this machine is unchecked. ByteNet may stay in the harness as a fourth column but is out of scope ([[Decisions/bytenet-out-of-scope]]). The published Kbps metric is compression-dominated and must not be used as an encoding-size comparison.
**Progress notes:**
- 2026-09-20: drafted from the handoff; nothing run.
Related: [[Research/blink-published-benchmark-and-changes-since]] [[Planning/volt-next-session-deliverables]] [[Library/handoff-2026-09-20]]
