---
type: research
date: 2026-09-20
session: 14e4b904
description: What Blink's published Blink-vs-Zap-vs-ByteNet benchmark measured, its numbers and caveats, how to reproduce it, and which releases since 2025-04-30 would move a re-run.
sources: [https://github.com/1Axen/blink/blob/main/benchmark/Benchmarks.md, https://github.com/1Axen/blink/tree/main/benchmark, "KB/Library/benchmark-and-changes-since-notes.md"]
tags: [blink, zap, benchmark, performance]
---
# Blink's published benchmark and what has changed since it ran
Up: [[Research]]

**Question:** What did the only first-party Blink vs Zap benchmark measure, can it be trusted, and what has changed since?

**Answer:**
- **Where:** `benchmark/Benchmarks.md` in the Blink repo, linked from the README, docs home and DevForum post. The harness lives in the same `benchmark/` folder: `Benchmarks.md`, `definitions/Definition.{blink,zap}`, `src/client/init.client.luau`, `src/server/init.server.luau`, `src/shared/benches/{Entities,Booleans}.luau`, `src/shared/modes/*.luau`, `build.bat`, `download.luau`, `generate.luau`, `run.luau`. Requires Roblox Studio, rojo, darklua, run-in-roblox. `download.luau` pulls `releases/latest` for every tool, so versions must be pinned by hand to reproduce anything.
- **Run:** 2025-04-30 19:45 UTC, **Blink v0.17.1 vs Zap v0.6.20 vs ByteNet v0.4.3**, Ryzen 9 7900X. Both were the newest releases that day. An earlier revision (2024-05-06) tested Blink v0.11.1 vs Zap v0.6.3. A 2025-10-24 line-ending commit changed no numbers.
- **Method:** client-side stress test in Studio via run-in-roblox. For each library and two payloads, the client fires the reliable event **1000 times per `PostSimulation` frame for 10 seconds with the same pre-built table**, sampling client FPS and `Stats.DataSendKbps` once per second; reports median, P0, P80, P90, P95, P100 and packet loss. Payloads: "Entities", an array of **100** six-`u8` structs (`id, x, y, z, orientation, animation`, random 1..255) though the schema allows `Entity[0..1000]`; "Booleans", 1000 literal `true`. Both events `Reliable`, `SingleSync`. Zap ran with defaults (`write_checks = true`); Blink 0.17.1 had just uncapped replication from 60 Hz.

| Scenario | Blink 0.17.1 | Zap 0.6.20 | ByteNet 0.4.3 | Roblox |
|---|---|---|---|---|
| Entities median FPS | **42** | 39 | 32 | 16 |
| Booleans median FPS | **97** | 52 | 35 | 21 |
| Entities Kbps (60-FPS normalised) | 41.81 | 41.71 | 41.64 | 559,364 |
| Booleans Kbps (60-FPS normalised) | 7.91 | 8.10 | 8.11 | 353,107 |

Packet loss 0% everywhere. Blink is +7.7% on Entities and +86.5% on Booleans relative to Zap. The README's "1.6 to 3.7x faster than Roblox" predates the 2025 run.
- **Caveats:** FPS is the cost of 1000 `Fire` calls per frame plus, because Studio runs client and server in one process, the server's deserialization; it is not an isolated serialize or deserialize microbenchmark, and only the first packet per run is content-validated. **Kbps is not an encoding-size comparison**: an identical buffer sent 1000 times per frame is compression-dominated, which is why three encodings land within 0.2% of each other; the author conceded in May 2024 that the metric rewarded faster libraries. Ten samples per run make percentiles coarse. No Zap maintainer has disputed the results; Zap publishes no benchmarks. The one independent 2025 comparison (Packet library thread, 2025-04-04, Zap 0.6.19 vs Blink 0.17.0) concluded "blink is slightly better than zap". Nothing from 2026 was found.
- **Changes since that would move a re-run:**

| Library and version | Change | Expected effect |
|---|---|---|
| Zap v0.6.22 | Inline resolved types | Fewer calls per `Entity`; Entities FPS up |
| Zap v0.6.24 / v0.6.25 | Bitpacking (#198); separate is-empty and length serde; mismatch fix | Booleans bytes and CPU down; likely the largest single mover |
| Zap v0.6.28 | `include_profile_labels` (keep off), `Reliable` default | Neutral |
| Blink v0.18.5 | `SyncValidation` on by default | Small added cost on the `SingleSync` receive side |
| Blink v0.18.7 / v0.18.9 | Register-exhaustion fix; NaN range validation | Neutral for u8 and boolean payloads |
| Blink 1.0.0-pre.6 | Optimized array reads | Receive-side speedup on both scenarios |
| Blink 1.0.0-pre.9 | Write validations off in `release`; enum storage | Send-side speedup in `release`; default profile may be slower than 0.18 |
| Blink 1.0 (all) | No bitpacking (#105 open) | Booleans encoding unchanged |

- **Re-run mechanics:** an unmodified run pulls Zap 0.6.29 and Blink 0.18.9, never a 1.0 pre-release. `Definition.zap` compiles unchanged on 0.6.29; `Definition.blink` is 0.x syntax. Running Blink 1.0 needs the definition ported (`type Entity = struct { ... }`, `event Booleans = { from: Client, ... }`), a profile chosen, and the harness adapters updated because they select `Event.Fire or Event.send` and `Event.On or Event.SetCallback or Event.listen`, while 1.0 exposes `blink.exports.<event>.fire`. Report Zap both with and without `opt write_checks = false` because Blink 0.18's `WriteValidations` defaults off and 1.0 `release` strips it. Whether Blink 0.17.1 performed write-side validation in the published run could not be established. Verify bitpacking by inspecting the `Booleans` writer in Zap 0.6.29's generated `Client.luau` before trusting any FPS delta.

**Sources:** Benchmarks.md and its history, the harness files, releases APIs for both repos, DevForum thread; cited notes in [[Library/benchmark-and-changes-since-notes]] (2026-09-20).
**Confidence:** high for the published numbers and version history; medium for the predicted effects of later releases, which are inferences from release notes.
**Applies to:** [[Planning/volt-benchmark-plan]]; sizing the performance goal in [[Decisions/volt-goals]].
Related: [[Research/zap-0-6-current-state]] [[Research/blink-current-state]] [[Research/zap-vs-blink-recommendation]]
