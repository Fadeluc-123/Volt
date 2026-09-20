---
type: library
date: 2026-09-20
session: 14e4b904
title: Blink benchmark and changes since (researcher notes)
origin: Research subagent, deep-research session ee3b949e, 2026-09-20
description: Researcher notes behind the report: nine questions on the published benchmark, its method, numbers, reproducibility and every relevant release since.
tags: [zap, blink, networking, snapshot]
---
# Blink's published benchmark (Blink vs Zap vs ByteNet) and what has changed in Blink and Zap since it was run
Up: [[Library]]

> Snapshot from 2026-09-20, kept verbatim for citations and detail. Current knowledge: [[Research/blink-published-benchmark-and-changes-since]]. If they disagree with this document, they win.

Research date: 2026-09-20. Note on dates: GitHub's HTML release pages, as summarized by the fetch tool, returned inconsistent or wrong years (e.g. "v0.17.1 April 29, 2023", "v1.0.0-pre.3 Feb 3, 2025"). All release dates below were therefore taken from the raw GitHub Releases API (`api.github.com/repos/<owner>/<repo>/releases`), which returns full ISO `published_at` timestamps. The single exception is Blink v0.17.1, whose exact API entry was truncated out of the fetch; its date is inferred (see Q3).

## Q1. Where is the benchmark published?

### Takeaway
The only first-party benchmark is a Markdown file inside the Blink repo, `benchmark/Benchmarks.md`, linked from the README, the docs homepage, and the DevForum post. There is no separate "Benchmarks" docs page and no separate `blink-benchmarks` repo; the full harness lives in the same `benchmark/` folder.

### Cited Findings
- The benchmark results file is `benchmark/Benchmarks.md` in the main Blink repo — [Benchmarks.md](https://github.com/1Axen/blink/blob/main/benchmark/Benchmarks.md)
- Blink's docs homepage lists only Getting Started (Installation, Introduction, CLI, Studio Plugin) and Language pages (Options, Scopes, Imports, Types, Events, Functions); it has no benchmark page and instead says "Benchmarks are available here" linking to the GitHub `benchmark/Benchmarks.md` file — [Blink docs](https://1axen.github.io/blink/)
- The README makes the same "Benchmarks are available here" link to `/benchmark/Benchmarks.md`; the repo's top-level folders are `.github/workflows/`, `.lune/`, `.vscode/`, `benchmark/`, `build/`, `docs/`, `plugin/`, `src/`, `test/` (182 stars, 36 forks, 489 commits at fetch time) — [1Axen/blink README](https://github.com/1Axen/blink)
- The README/DevForum headline claim is "1.6-3.7x faster than ROBLOX" and "1000x less bandwidth than ROBLOX" — [Blink DevForum thread](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671); [README](https://github.com/1Axen/blink)
- The DevForum thread ("Blink | An IDL compiler written in Luau for ROBLOX buffer networking | 0.18.5", topic 2959671) was posted May 6, 2024 and links to the same GitHub Benchmarks.md rather than embedding numbers — [Blink DevForum thread](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671)
- The `benchmark/` directory contains: folders `definitions/` and `src/`; files `.darklua.json`, `Benchmarks.md`, `Performance.luau`, `build.bat`, `build.project.json`, `default.project.json`, `config.json.example`, `download.luau`, `generate.luau`, `run.luau` — [benchmark folder](https://github.com/1Axen/blink/tree/main/benchmark)
- Commit history of Benchmarks.md shows exactly three commits: "Updated benchmarks to new layout" (Axen, August 10, 2024, 720048b); "chore: update benchmarks" (1Axen, April 30, 2025, 56410a5); "convert line ending to LF" (1Axen, October 24, 2025, 01e2b15) — [Benchmarks.md history](https://github.com/1Axen/blink/commits/main/benchmark/Benchmarks.md)

### Inferences
- The published numbers were last regenerated on 2025-04-30; the October 2025 commit was a line-ending change only, so no re-run has been published in the 17 months since.
- Searches for a separate repo named like "blink-benchmarks" / "zap-vs-blink" returned nothing; the third-party repo `nezuo/roblox-serde-benchmarks` (see Q9) appears to be the ancestor of 1Axen's harness (same Booleans/Entities-style scenarios).

### Gaps
- I could not access Discord, so any benchmark discussion there is unrecorded.

## Q2. What exactly did the benchmark measure, and how was it built?

### Takeaway
It is a client-side stress test run inside Roblox Studio via `run-in-roblox`: for each library and each of two payloads (an array of 100 six-byte structs; an array of 1000 `true` booleans), the client fires the reliable event 1000 times per `PostSimulation` frame for 10 seconds using the same pre-built table every time, while sampling the client frame rate and `Stats.DataSendKbps` once per second. The reported metrics are FPS percentiles, a 60-FPS-normalized Kbps figure, and packet loss (sent vs. received on the server). It does not measure per-call serialize/deserialize time, bytes per packet, allocations, or memory.

### Cited Findings

Methodology statement and metrics:
- Verbatim methodology line: "Benchmarks are done by firing the event 1000 times per frame with the same data every frame for 10 seconds." — [Benchmarks.md (raw)](https://raw.githubusercontent.com/1Axen/blink/main/benchmark/Benchmarks.md)
- Tables report, per tool, Median, P0, P80, P90, P95, P100 and "Loss (%)" for two metrics, FPS and Kbps, across two scenarios, "Entities" and "Booleans" — [Benchmarks.md (raw)](https://raw.githubusercontent.com/1Axen/blink/main/benchmark/Benchmarks.md)

Payload definitions (the data shapes):
- `Definition.blink` (verbatim): `option ClientOutput = "../src/shared/blink/Client.luau"`, `option ServerOutput = "../src/shared/blink/Server.luau"`, `struct Entity { id: u8, x: u8, y: u8, z: u8, orientation: u8, animation: u8 }`, `event Booleans { From: Client, Type: Reliable, Call: SingleSync, Data: boolean[0..1000] }`, `event Entities { From: Client, Type: Reliable, Call: SingleSync, Data: Entity[0..1000] }` — [Definition.blink](https://github.com/1Axen/blink/blob/main/benchmark/definitions/Definition.blink)
- `Definition.zap` (verbatim): `opt client_output = "../src/shared/zap/Client.luau"`, `opt server_output = "../src/shared/zap/Server.luau"`, `type Entity = struct { id: u8, x: u8, y: u8, z: u8, orientation: u8, animation: u8 }`, `event Booleans = { from: Client, type: Reliable, call: SingleSync, data: boolean[0..1000] }`, `event Entities = { from: Client, type: Reliable, call: SingleSync, data: Entity[0..1000] }` — [Definition.zap](https://github.com/1Axen/blink/blob/main/benchmark/definitions/Definition.zap)
- The Zap definition sets no other options, so Zap ran with defaults: `write_checks = true` ("Type checking during network writes; disables in production"), `manual_event_loop = false` ("Determines if Zap automatically sends reliable events and functions each Heartbeat"), `casing = PascalCase`, `remote_scope/remote_folder = "ZAP"` — [Zap options docs](https://zap.redblox.dev/config/options.html)
- The `definitions/` folder contains only `Definition.blink` and `Definition.zap`; there is no ByteNet definition file (ByteNet is defined in Luau, so it is presumably declared in its `modes/bytenet.luau` adapter) — [definitions folder](https://github.com/1Axen/blink/tree/main/benchmark/definitions)
- Test data, Entities: `benches/Entities.luau` creates 100 entities (`for Index = 1, 100 do`), each field (`id, x, y, z, orientation, animation`) a random integer 1–255, no seed — [Entities.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/shared/benches/Entities.luau)
- Test data, Booleans: `benches/Booleans.luau` is `return table.create(1000, true)` (1000 fixed `true` values) — [Booleans.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/shared/benches/Booleans.luau)
- Note the mismatch: the schemas allow `Entity[0..1000]` but the Entities payload actually sent is 100 elements; the Booleans payload is the full 1000 — [Entities.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/shared/benches/Entities.luau); [Definition.blink](https://github.com/1Axen/blink/blob/main/benchmark/definitions/Definition.blink)

Harness (client):
- `src/client/init.client.luau` iterates `for Tool in Modes do` and `for Bench in Benches do`; fires on `RunService.PostSimulation:Connect(function(DeltaTime: number)` with `for Index = 1, 1000 do Sent += 1 Method(Data) end`; runs each combination for `task.wait(10)`; `local MAXIMUM_FRAMERATE = 60` — [init.client.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/client/init.client.luau)
- Framerate: a `Frames` counter is reset each second (`if Total >= 1 then Total -= 1` ... `Frames = 0`) and one FPS sample stored per second; FPS samples are sorted descending `table.sort(Framerates, function(a, b) return a > b end)`, bandwidth samples ascending `table.sort(Bandwidth)` — [init.client.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/client/init.client.luau)
- Bandwidth: sampled once per second from Roblox `Stats.DataSendKbps` and scaled to a 60-FPS equivalent: `local Scale = (MAXIMUM_FRAMERATE / Frames)` then `table.insert(Bandwidth, Stats.DataSendKbps * Scale)`; no rationale comment in code — [init.client.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/client/init.client.luau)
- Percentiles: `for _, Percentage in { 50, 0, 80, 90, 95, 100 } do` with `local Index = ((#Samples * (Percentile / 100)) // 1)` — [init.client.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/client/init.client.luau)
- Rest between runs: `WaitForPacketsToProcess()` loops `while Stats.DataSendKbps > 0.5` then `task.wait(5)`; no explicit warm-up or reset — [init.client.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/client/init.client.luau)
- Firing method per tool: `if Tool == "warp"` and `elseif Tool == "roblox"` are special-cased; all others use `Event.Fire or Event.send`; the client contains no call to `SendEvents` or any manual event-loop function — [init.client.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/client/init.client.luau)
- Received count obtained via `local Recieved = ReplicatedStorage.Shared.GetRecieved:InvokeServer()`; results are JSON-encoded and sent with `ReplicatedStorage.Shared.Generate:FireServer(HttpService:JSONEncode(Results))` — [init.client.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/client/init.client.luau)

Harness (server):
- `src/server/init.server.luau` connects each tool's event (warp: `Event:Connect(Callback)`; roblox: `Event.OnServerEvent:Connect(Callback)`; others: `Event.On or Event.SetCallback or Event.listen`), increments `BenchRecieved[Tool] += 1` per packet, validates only the first packet against the expected data via a recursive `CompareValues()` (`if BenchRecieved[Tool] > 1 then return`), warns `Recieved incorrect data with {Tool} for {Name}` on mismatch, serves counts via `GetRecieved.OnServerInvoke`, and on `Generate` writes a StringValue named "Result" parented to `game` — [init.server.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/server/init.server.luau)

Adapters:
- `modes/init.luau` requires every child module into a `Modes` table, skipping a hardcoded `DISABLED_MODES` table that currently contains `warp = true` — [modes/init.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/shared/modes/init.luau)
- `modes/` contains `blink.luau`, `bytenet.luau`, `init.luau`, `roblox.luau`, `warp.luau`, `zap.luau` — [modes folder](https://github.com/1Axen/blink/tree/main/benchmark/src/shared/modes)
- `modes/zap.luau` is only: `if RunService:IsServer() then return require("../zap/Server") elseif RunService:IsClient() then return require("../zap/Client") end` (i.e. the generated Zap module is used directly, no wrapper, no manual event loop) — [modes/zap.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/shared/modes/zap.luau)
- `modes/blink.luau` is the identical pattern for `../blink/Server` / `../blink/Client` — [modes/blink.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/shared/modes/blink.luau)

Build/run pipeline:
- `build.bat` (verbatim steps): optional `lune run download` into `./tools` and `./packages`; then `"./tools/zap.exe" "./definitions/Definition.zap"` and `"./tools/blink.exe" "./definitions/Definition.blink"`; then `rojo sourcemap default.project.json ...`, `darklua process src roblox`, `rojo build build.project.json --output "./Benchmark.rbxl"`; then optionally `lune run generate` — [build.bat](https://github.com/1Axen/blink/blob/main/benchmark/build.bat)
- `download.luau` fetches zap from `https://api.github.com/repos/red-blox/zap/releases/latest` and blink from `https://api.github.com/repos/1Axen/blink/releases/latest`, keeping only `windows-x86_64` assets, extracts with 7-Zip into `./tools/`; fetches ByteNet from `https://api.github.com/repos/ffrostflame/ByteNet/releases` (newest by id) and its contents from `https://api.wally.run/v1/package-contents/ffrostflame/bytenet/`; writes all tag names to `./tools/versions.json` — [download.luau](https://github.com/1Axen/blink/blob/main/benchmark/download.luau)
- `generate.luau` runs `process.exec("run-in-roblox", { "--place", "Benchmark.rbxl", "--script", "run.luau" })`, reads versions from `./tools/versions.json`, queries hardware with `wmic` (`QueryWMIC("cpu", "name")`, `QueryWMIC("memorychip", "Capacity,Speed")`), computes `Loss = math.floor((1 - (Result.Recieve / Result.Sent)) * 100)`, and appends a timestamp, versions, specs and result tables (`|Tool ({Metric.Label})|Median|P0|P80|P90|P95|P100|Loss (%)|`) after a separator in Benchmarks.md; the percentiles themselves come pre-computed from the client — [generate.luau](https://github.com/1Axen/blink/blob/main/benchmark/generate.luau)
- `run.luau` (the script run-in-roblox injects) prints "Press F5 to start the benchmark." if not running, then polls `game:FindFirstChild("Result")` every second and prints `--RESULTS JSON--` followed by the value — [run.luau](https://github.com/1Axen/blink/blob/main/benchmark/run.luau)
- `config.json.example` is just `{ "github-token": "" }` (used by download.luau for GitHub API auth) — [config.json.example](https://github.com/1Axen/blink/blob/main/benchmark/config.json.example)
- `Performance.luau` is unrelated to the network benchmark: it benchmarks Blink's own compiler (Lex, Parse, Generate; 1,000 iterations, `os.clock()`, median/P0/P90/P95) — [Performance.luau](https://github.com/1Axen/blink/blob/main/benchmark/Performance.luau)

### Inferences
- What the FPS column actually captures: client-side cost of 1000 `Fire` calls per frame (argument handling, validation if any, buffer serialization, and the library's per-frame batching/flush) plus, because run-in-roblox runs Studio play mode with client and server in the same process, the server-side deserialization of those packets. It is not an isolated serialize-only or deserialize-only microbenchmark.
- The Kbps column is not a measure of encoding size. Raw uncompressed payload for Entities is about 600 bytes x 1000 fires = ~600 KB per frame at ~40 FPS (tens of MB/s), yet the reported figure is ~42 Kbps; for Booleans ~1 MB per frame at ~97 FPS versus 7.9 Kbps. Sending an identical buffer 1000 times per frame is extremely compressible, so transport-level batching/compression must dominate `DataSendKbps`. This also explains why Blink, Zap and ByteNet report near-identical Kbps (41.81 / 41.71 / 41.64 and 7.91 / 8.10 / 8.11) despite different encodings. Treat Kbps as a sanity check, not a comparison metric. (My inference from the harness code and arithmetic; not stated by the author.)
- The `* (60 / Frames)` scaling normalizes bandwidth to what it would be at 60 FPS; this was added after the author acknowledged in 2024 that faster libraries showed higher Kbps simply because they got through more frames (see Q6).
- Because neither adapter wraps the generated modules, Zap ran with its default automatic Heartbeat event loop (batching the 1000 fires into one remote call per frame) and with `write_checks = true`. Blink 0.17.1's release note "Client side automatic replication is no longer capped at 60 Hz" (published the day before the run) means Blink also flushed automatically per frame.
- Only the first packet per tool/bench is content-validated on the server; loss is purely a count comparison.

### Gaps
- I did not fetch `modes/bytenet.luau`, `modes/roblox.luau`, `modes/warp.luau`, `benches/init.luau`, `.darklua.json`, or the two `.project.json` files; their exact contents (e.g. the ByteNet packet definition and whether the Roblox baseline sends the table or a buffer) are unverified.
- The client script's exact handling of P0 index 0 (whether clamped to 1) was not visible; the compiler benchmark clamps with `math.max(Index, 1)`.
- Whether Blink 0.17.1 performed write-side validation comparable to Zap's `write_checks` is not established from the sources.

## Q3. Which versions were used, and when was it run?

### Takeaway
The published run is stamped 2025-04-30 19:45:09 UTC with blink v0.17.1, zap v0.6.20 and bytenet v0.4.3, on a Ryzen 9 7900X. Both Blink and Zap were the newest releases available that day (Blink v0.17.1 had shipped the day before; Zap v0.6.20 17 days before), consistent with the download script pulling `releases/latest`.

### Cited Findings
- Header (verbatim): "Updated: 2025-04-30 19:45:09 UTC"; `blink`: v0.17.1; `zap`: v0.6.20; `bytenet`: v0.4.3; "Processor: AMD Ryzen 9 7900X 12-Core Processor"; "Memory #1: 17GB 4800"; "Memory #2: 17GB 4800" — [Benchmarks.md (raw)](https://raw.githubusercontent.com/1Axen/blink/main/benchmark/Benchmarks.md)
- The "chore: update benchmarks" commit is dated April 30, 2025 — [Benchmarks.md history](https://github.com/1Axen/blink/commits/main/benchmark/Benchmarks.md)
- Zap v0.6.20 `published_at` 2025-04-13T10:47:02Z (not prerelease) — [Zap releases API](https://api.github.com/repos/red-blox/zap/releases?per_page=100)
- Blink v0.17.0 `published_at` 2025-03-24T17:07:41Z; v0.17.4 2025-06-27T20:13:37Z; v0.16.0 2025-03-18; v0.15.6 2025-03-11 — [Blink releases API p3](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=3); [Blink releases API p2](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=2)
- Blink v0.17.1 release page: date rendered as "April 29" (the fetch tool reported the year as 2023, which is impossible given v0.17.0 = 2025-03-24); notes: "Client side automatic replication is no longer capped at 60 Hz." and "Fix buffer offset variable shadowing in allocation merged blocks by @daimond113" — [Blink v0.17.1 release](https://github.com/1Axen/blink/releases/tag/v0.17.1)
- Blink HTML release list (page 3) orders v0.17.0 (24 Mar), v0.17.2 (10 May), v0.17.3 (18 May), v0.17.4 (27 Jun) — [Blink releases page 3](https://github.com/1Axen/blink/releases?page=3)
- The download script pins nothing; it always fetches `releases/latest` for both Zap and Blink and the newest ByteNet release — [download.luau](https://github.com/1Axen/blink/blob/main/benchmark/download.luau)
- The tables use a Studio session driven by `run-in-roblox` (not a live server) — [generate.luau](https://github.com/1Axen/blink/blob/main/benchmark/generate.luau)

### Inferences
- Blink v0.17.1 was published 2025-04-29 (year inferred from the API ordering v0.17.0 = 2025-03-24 < v0.17.1 < v0.17.2 and the tag page's "April 29"). That makes it "latest" on 2025-04-30 and resolves the apparent oddity of a "0.17.x" version in a 2025 run.
- ByteNet v0.4.3 was presumably the newest ByteNet GitHub release on that date (not verified independently).
- "34GB" quoted in some search snippets is the sum of the two 17GB `wmic` capacity readings (likely 2 x 16 GiB reported in decimal GB).

### Gaps
- The exact ISO timestamp for Blink v0.17.1 was cut from the truncated API response; the day is from the HTML tag page.
- Roblox Studio version used on 2025-04-30 is not recorded anywhere in the repo.

## Q4. What were the reported numbers?

### Takeaway
Blink led both scenarios on FPS: Entities 42 median vs Zap 39 vs ByteNet 32 vs Roblox 16 (Blink ~8% faster than Zap); Booleans 97 vs 52 vs 35 vs 21 (Blink ~87% faster than Zap). Normalized Kbps was essentially identical among the three buffer libraries and 4–5 orders of magnitude below native Roblox. Packet loss was 0% everywhere.

### Cited Findings (all verbatim from [Benchmarks.md (raw)](https://raw.githubusercontent.com/1Axen/blink/main/benchmark/Benchmarks.md))

Entities, FPS:

|Tool|Median|P0|P80|P90|P95|P100|Loss (%)|
|---|---|---|---|---|---|---|---|
|roblox|16.00|16.00|15.00|15.00|15.00|15.00|0%|
|blink|42.00|45.00|42.00|42.00|42.00|42.00|0%|
|zap|39.00|40.00|38.00|38.00|38.00|38.00|0%|
|bytenet|32.00|34.00|32.00|32.00|32.00|31.00|0%|

Entities, Kbps:

|Tool|Median|P0|P80|P90|P95|P100|Loss (%)|
|---|---|---|---|---|---|---|---|
|roblox|559364.31|559364.31|676715.68|676715.68|676715.68|784081.75|0%|
|blink|41.81|26.30|42.40|42.48|42.48|42.62|0%|
|zap|41.71|25.46|42.19|42.32|42.32|42.93|0%|
|bytenet|41.64|22.84|42.36|42.82|42.82|43.24|0%|

Booleans, FPS:

|Tool|Median|P0|P80|P90|P95|P100|Loss (%)|
|---|---|---|---|---|---|---|---|
|roblox|21.00|22.00|20.00|19.00|19.00|19.00|0%|
|blink|97.00|98.00|97.00|96.00|96.00|96.00|0%|
|zap|52.00|53.00|51.00|51.00|51.00|49.00|0%|
|bytenet|35.00|37.00|35.00|35.00|35.00|34.00|0%|

Booleans, Kbps:

|Tool|Median|P0|P80|P90|P95|P100|Loss (%)|
|---|---|---|---|---|---|---|---|
|roblox|353107.13|196826.86|690747.68|842240.25|842240.25|1124176.38|0%|
|blink|7.91|7.41|7.93|7.99|7.99|8.00|0%|
|zap|8.10|5.75|8.17|8.22|8.22|8.27|0%|
|bytenet|8.11|5.07|8.35|8.46|8.46|8.47|0%|

- Only 10 samples per run exist (one per second for 10 s), so P80/P90/P95 often coincide (index = floor(10 x p)) — [init.client.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/client/init.client.luau)
- Because FPS samples are sorted descending, the "P0" FPS column is the best second and "P100" the worst; Kbps is sorted ascending so P0 is the lowest — [init.client.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/client/init.client.luau)

### Inferences
- Relative to Zap: Blink +7.7% median FPS on Entities (42/39) and +86.5% on Booleans (97/52). Relative to ByteNet: +31% and +177%.
- The Booleans gap is the headline result and is also the one most exposed to later changes (Zap's v0.6.24 bitpacking; Blink's 1.0 changes), see Q7/Q8.
- The README's "1.6-3.7x faster than ROBLOX" does not match these tables (42/16 = 2.6x, 97/21 = 4.6x); it likely predates the 2025 re-run.

### Gaps
- No per-operation timings (microseconds per Fire, per deserialize) exist in the published data.

## Q5. Is the benchmark source included so it can be reproduced?

### Takeaway
Yes. Everything except the compiled `Benchmark.rbxl` and the downloaded tool binaries is in `1Axen/blink/benchmark/` (definitions, harness, adapters, build/download/generate scripts). The place file is produced locally by `build.bat`. Reproducing the *exact* 2025-04-30 run requires manually pinning Blink v0.17.1, Zap v0.6.20 and ByteNet v0.4.3 because the download script always fetches latest.

### Cited Findings
- Source layout: `benchmark/definitions/{Definition.blink, Definition.zap}`; `benchmark/src/client/init.client.luau`; `benchmark/src/server/init.server.luau`; `benchmark/src/shared/benches/{Booleans.luau, Entities.luau, init.luau}`; `benchmark/src/shared/modes/{blink, bytenet, init, roblox, warp, zap}.luau`; generated code goes to `src/shared/blink/` and `src/shared/zap/` (not committed; created by build.bat) — [benchmark folder](https://github.com/1Axen/blink/tree/main/benchmark); [benches](https://github.com/1Axen/blink/tree/main/benchmark/src/shared/benches); [modes](https://github.com/1Axen/blink/tree/main/benchmark/src/shared/modes); [build.bat](https://github.com/1Axen/blink/blob/main/benchmark/build.bat)
- Required external tools per the scripts: `lune` (runs download/generate), `7-Zip` (extraction), `rojo` (sourcemap + build), `darklua` (process `src` -> `roblox`), `run-in-roblox` (launches Studio with `Benchmark.rbxl` and `run.luau`), Windows `wmic` (hardware info); Zap and Blink are used as `./tools/zap.exe` and `./tools/blink.exe` (windows-x86_64 only) — [build.bat](https://github.com/1Axen/blink/blob/main/benchmark/build.bat); [download.luau](https://github.com/1Axen/blink/blob/main/benchmark/download.luau); [generate.luau](https://github.com/1Axen/blink/blob/main/benchmark/generate.luau)
- The `Benchmark.rbxl` is not committed (it is a build output of `rojo build build.project.json --output "./Benchmark.rbxl"`) — [build.bat](https://github.com/1Axen/blink/blob/main/benchmark/build.bat)
- Warp is present as an adapter but disabled via `DISABLED_MODES` — [modes/init.luau](https://github.com/1Axen/blink/blob/main/benchmark/src/shared/modes/init.luau)
- The author's rokit/pesde tool manifests (`rokit.toml`, `pesde.toml`) are at repo root — [1Axen/blink README](https://github.com/1Axen/blink)

### Inferences
- For a "same benchmark, current versions" re-run: keep `Definition.blink`/`Definition.zap` as-is but note that Zap v0.6.24+ deprecates nothing used here (no `string`/`Instance` types), so the Zap file should compile unchanged on v0.6.29; the Blink file uses the 0.x syntax, so it compiles on v0.18.9 but would need rewriting for the v1.0.0-pre.x syntax (see Q8).
- For an apples-to-apples fairness pass, consider also running with `opt write_checks = false` in Zap and Blink's `release` profile (1.0 pre) / equivalent, since Zap's docs say write checks are meant to be disabled in production.

### Gaps
- The benchmark uses `require("../zap/Server")`-style string requires and `.luau` sources processed by darklua; the exact `.darklua.json` rules and `build.project.json` tree were not fetched.
- Versions of rojo/darklua/lune/run-in-roblox used in April 2025 are not recorded in the benchmark folder (the root `rokit.toml` may pin some; not fetched).

## Q6. Did anyone critique the methodology or dispute the results?

### Takeaway
I found no public critique or rebuttal from jackdotink or any Zap maintainer, and no GitHub issue in red-blox/zap about Blink's benchmark. The only recorded methodology discussion is on Blink's own DevForum thread in May 2024, where a community member asked for Warp to be included and for "P0" to be reduced, and the author himself conceded that the Kbps metric rewarded faster libraries and that he was looking for a better method.

### Cited Findings
- RaterixRGL (May 17, 2024) on the Blink thread requested that Warp be included in the tests and suggested reducing "P0 further" — [Blink DevForum thread](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671)
- Ax3nx (1Axen) replied that Warp had been included before but stopped working, and on Kbps: "the faster something runs the higher the kbps is due to it being able to send more packets per second", adding he was seeking improved benchmarking methodology — [Blink DevForum thread](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671)
- Page 2 of the Blink thread (June–October 2024 replies) contains no benchmark disputes; the only Zap mention is Riesegarder (June 3, 2024) musing about making "my own networking thing ala Zap except in Studio" — [Blink DevForum thread page 2](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=2)
- The "Best Network library" thread (page 2) only references that Blink's benchmarks exist (TimeFrenzied, May 28, 2025); no critique — [Best Network library](https://devforum.roblox.com/t/best-network-library/3667044?page=2)
- Searches of red-blox/zap issues for "blink" surfaced only unrelated issues (e.g. #225 "Sharding of the generated module is needed for larger games") — [Zap issues](https://github.com/red-blox/zap/issues); [Issue #225](https://github.com/red-blox/zap/issues/225)
- Blink's README credits Zap for its range and array syntax, indicating a cordial rather than adversarial relationship — [search result summarizing README](https://github.com/1Axen/blink)

### Inferences
- The `Scale = 60 / Frames` normalization in the current client harness appears to be the author's response to his own 2024 Kbps concern; the current Kbps figures are therefore already "frame-rate corrected".
- Methodology weaknesses evident from the code (my analysis, not published critiques): (1) identical payload every fire makes Kbps compressibility-dominated and meaningless as an encoding-size comparison; (2) 10 samples per run makes percentiles coarse; (3) Entities is 100 elements, not the 1000 the schema and prose might suggest; (4) client and server share one Studio process, so server deserialization cost bleeds into client FPS; (5) no seed for Entities data; (6) Zap ran with `write_checks = true` (a production-off setting) while Blink's equivalent validation state at 0.17.1 is undocumented; (7) nothing measures receive-side cost or per-call latency separately.

### Gaps
- Discord (where Zap and Blink maintainers are most active) was not accessible; any critique there is unrecorded.
- I did not locate Zap's own DevForum resource thread via search, so I cannot rule out a reply there that mentions Blink's numbers.
- The Blink DevForum thread has many pages beyond page 2 that I did not fetch.

## Q7. What has changed in Zap since v0.6.20 (2025-04-13) that could plausibly change results?

### Takeaway
Zap shipped nine releases (v0.6.21–v0.6.29, 2025-06-22 to 2026-06-23). The ones that plausibly move this benchmark are v0.6.22 (inline resolved types, i.e. the `Entity` struct can be inlined into the array loop), v0.6.24 (bitpacking plus separated "is empty"/length serde, which should shrink and speed the 1000-boolean array), and v0.6.25 (bitpacking mismatch fix). There were no changes to `manual_event_loop`, the Heartbeat event loop, or CFrame encoding in this window; `write_checks` remains on by default. A `rewrite` branch also exists.

### Cited Findings (dates from [Zap releases API](https://api.github.com/repos/red-blox/zap/releases?per_page=100); notes from [Zap releases](https://github.com/red-blox/zap/releases))
- Baseline v0.6.20 (2025-04-13): added OR type syntax and ordered unreliables; fixed unreliable polling, generated modules always returning, and the buffer length check with `write_checks`; optimizations: NumTy algorithm offsets, "optimized table-like length storage", improved map & set size accuracy, fixed inaccurate `Ty::size`, corrected unit enum size, added assertion messages — [Zap releases](https://github.com/red-blox/zap/releases)
- v0.6.21 (2025-06-22): namespaces; fixed recursive type regression; TypeScript iteration; loosened set & list type restrictions; fixed inaccurate variants value — [Zap releases](https://github.com/red-blox/zap/releases)
- v0.6.22 (2025-06-24): "Inline resolved types where possible" (optimization); nested types resolve correctly; set types relaxed to `{ [ty]: any }` — [Zap releases](https://github.com/red-blox/zap/releases)
- v0.6.23 (2025-06-25): fixed v0.6.22 regression preventing builtin types inside namespaces — [Zap releases](https://github.com/red-blox/zap/releases)
- v0.6.24 (2025-07-11): "Add bitpacking" (#198); "Separate is empty and length serde" (#201); `string` deprecated in favour of `string.binary` (same behaviour) or `string.utf8` (validates UTF-8); `Instance (Model)` -> `Instance.Model`; TypeScript `const enums`; playground serialization fix; export name conflict prevention; MSRV bumped to Rust 1.88.0 (2024 edition); contributors sasial-dev, daimond113 — [Zap v0.6.24 release](https://github.com/red-blox/zap/releases/tag/v0.6.24)
- v0.6.25 (2025-07-21): "Fix bitpacking mismatch" — [Zap releases](https://github.com/red-blox/zap/releases)
- v0.6.26 (2025-09-28): validation for duplicate Zap instances sharing `remote_scope`/`remote_folder` — [Zap releases](https://github.com/red-blox/zap/releases)
- v0.6.27 (2025-10-05): fixed a rare buffer access out-of-bounds error with more than 256 concurrent function calls — [Zap releases](https://github.com/red-blox/zap/releases)
- v0.6.28 (2025-12-13): added `include_profile_labels` option (microprofiler labels, default false); `Reliable` is now the default event type; event name comments added to deserialization code; IsServer/IsClient check ordering fix — [Zap releases](https://github.com/red-blox/zap/releases); [Zap options docs](https://zap.redblox.dev/config/options.html)
- v0.6.29 (2026-06-23): allow requiring zap from edit mode (Storyboards); docs updates for deprecated syntax — [Zap releases](https://github.com/red-blox/zap/releases)
- Pre-baseline context (already in v0.6.20): v0.6.17 (2025-01-26) added the `vector` type, split event IDs by server/client and reliable/unreliable, stopped passing an ID for unreliable events (saves 1–2 bytes), and introduced a test suite; v0.6.18 (2025-02-20) added polling, `types_output`, and raised the unreliable size limit; v0.6.19 (2025-03-08) "Optimize length storage" and fixed tagged variant index serialization — [Zap releases page 2](https://github.com/red-blox/zap/releases?page=2); [Zap releases API p2](https://api.github.com/repos/red-blox/zap/releases?per_page=10&page=2)
- `manual_event_loop` (default false) is documented as: "Determines if Zap automatically sends reliable events and functions each Heartbeat"; when enabled a `SendEvents` function must be called manually; the docs note (dated January 2024) that firing remotes above 60 Hz can cause very high server network response times — [Zap options docs](https://zap.redblox.dev/config/options.html); [search snippet of same page](https://zap.redblox.dev/config/options.html)
- `write_checks` default `true`: "Type checking during network writes; disables in production" — [Zap options docs](https://zap.redblox.dev/config/options.html)
- Zap has a `rewrite` branch (README at `red-blox/Zap/blob/rewrite/README.md`) alongside a `0.6.x` branch — [Zap rewrite README](https://github.com/red-blox/Zap/blob/rewrite/README.md); [zap 0.6.x package.json](https://github.com/red-blox/zap/blob/0.6.x/package.json)

### Inferences
- Booleans scenario: if v0.6.24 bitpacking applies to `boolean[]` (the release note does not enumerate covered types), a 1000-boolean array shrinks from ~1000 bytes to ~125 bytes and the per-element write becomes a bit operation; this could substantially change both Zap's FPS and bytes in the scenario where Blink led by 87%. Verify by inspecting the generated `Client.luau` from Zap v0.6.29 for the Booleans event.
- Entities scenario: v0.6.22's inlining of resolved types removes a function call per `Entity` in the array loop (100 per fire, 100,000 per frame), which is exactly the hot path here; expect a measurable FPS change.
- v0.6.28's `include_profile_labels` gives a cheap way to get per-event microprofiler timings in a re-run, but must stay `false` for the comparison run.
- Nothing in v0.6.21–v0.6.29 changes reliable-event batching, so the per-frame flush behaviour matches the 2025 run.

### Gaps
- Zap has no CHANGELOG.md at `red-blox/zap/main` (404); the releases page is the changelog. I did not read PRs #198/#201 to confirm exactly which types bitpacking covers.
- The `rewrite` branch's status, version target, and performance changes were not researched.

## Q8. What has changed in Blink since v0.17.1 (2025-04-29) that could plausibly change results?

### Takeaway
Blink split into two lines. The 0.x stable line (v0.17.2 through v0.18.9, 2025-05-10 to 2026-09-19) mostly changed tooling, TypeScript output, and validation (SyncValidation on by default from v0.18.5; removal of redundant instance assertions in v0.18.7), with little that touches u8-struct or boolean array serialization. The v1.0.0-pre.x rewrite (pre.1 2026-01-14 through pre.10 2026-09-19) changes syntax, adds compilation profiles, optimizes array reads (pre.6) and enum storage (pre.9), and disables write validations in the `release` profile (pre.9); the benchmark's `Definition.blink` would need porting to run on it.

### Cited Findings (dates from [Blink releases API p1](https://api.github.com/repos/1Axen/blink/releases?per_page=100), [p2](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=2), [p3](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=3); notes from [Blink releases](https://github.com/1Axen/blink/releases), [page 2](https://github.com/1Axen/blink/releases?page=2), [page 3](https://github.com/1Axen/blink/releases?page=3))

0.x line:
- v0.17.2 (2025-05-10): fixed array ranges with upper bounds not parsing correctly — [Blink releases page 3](https://github.com/1Axen/blink/releases?page=3)
- v0.17.3 (2025-05-18): TypeScript codegen now emits `field?: type`; deprecated `Poll` field in events — [Blink releases page 3](https://github.com/1Axen/blink/releases?page=3)
- v0.17.4 (2025-06-27): fixed decimal number parsing in the Studio plugin editor — [Blink releases page 3](https://github.com/1Axen/blink/releases?page=3)
- v0.18.0 (2025-08-01): Promise type inference; path import support — [Blink releases page 2](https://github.com/1Axen/blink/releases?page=2)
- v0.18.1 (2025-08-11): absolute path handling in output — [Blink releases page 2](https://github.com/1Axen/blink/releases?page=2)
- v0.18.2 (2025-09-29): TypeScript generation fix for Polling events — [Blink releases page 2](https://github.com/1Axen/blink/releases?page=2)
- v0.18.3 (2025-09-30): reverted to zip compression; v0.18.4 (2025-10-01): compression format changes (release packaging, not codegen) — [Blink releases page 2](https://github.com/1Axen/blink/releases?page=2)
- v0.18.5 (2025-10-24): Lune upgrade; SyncValidation improvements; SyncValidation now default — [Blink releases page 2](https://github.com/1Axen/blink/releases?page=2)
- v0.18.6 (2025-10-24): fixed unit packs (tuples) code generation — [Blink releases page 2](https://github.com/1Axen/blink/releases?page=2)
- v0.18.7 (2026-02-13): added linting directives; removed redundant instance assertions; fixed "out of local registers" caused by excessive serdes functions — [Blink releases](https://github.com/1Axen/blink/releases)
- v0.18.8 (2026-04-11): Studio plugin editor cursor/selection fixes; fixed DateTime read cursor advancement (1 -> 8 bytes); autocomplete navigation — [Blink releases](https://github.com/1Axen/blink/releases)
- v0.18.9 (2026-09-19, current "latest" per `releases/latest`): fixed NaN values bypassing inexact range validation for floats and vectors; updated validation error messaging — [Blink releases/latest API](https://api.github.com/repos/1Axen/blink/releases/latest); [Blink releases](https://github.com/1Axen/blink/releases)
- SyncValidation was introduced as an option in v0.17.0 (2025-03-24) "for checking yielding in Sync callbacks"; functions gained server-side listener yielding; also "Fixed serdes code for exact size buffers" — [Blink releases page 3](https://github.com/1Axen/blink/releases?page=3)

1.0 pre-release line (all `prerelease: true`):
- v1.0.0-pre.1 (2026-01-14): "The blink rewrite" — syntax largely changed; exports nested under `.exports`; literal types, recursive types, union types; compilation profiles; `StreamedInstance` replaces `Instance?`; validation features enabled by default; Promise/Future support removed in favour of "small wrappers" — [Blink releases API p2](https://api.github.com/repos/1Axen/blink/releases?per_page=12&page=2); [Blink releases page 2](https://github.com/1Axen/blink/releases?page=2)
- v1.0.0-pre.2 (2026-01-17): type resolution/parsing fixes; Windows diagnostics encoding; v1.0.0-pre.3 (2026-02-03): new import syntax with destructuring; casing and length-check fixes — [Blink releases page 2](https://github.com/1Axen/blink/releases?page=2)
- v1.0.0-pre.4 (2026-02-09): fixed empty buffer sending; into-scope imports generating empty tables; empty function parsing — [Blink releases](https://github.com/1Axen/blink/releases)
- v1.0.0-pre.5 (2026-03-15): fixed batched events early-exit issue — [Blink releases](https://github.com/1Axen/blink/releases)
- v1.0.0-pre.6 (2026-04-11): exposed internal `nil` singleton type; "Optimized array reads"; server deserialization exits early if the player leaves; added `integer` (int64) type — [Blink releases](https://github.com/1Axen/blink/releases)
- v1.0.0-pre.7 (2026-08-24): upgraded lute to 1.0.0; better syntax error reporting; keyword-as-identifier parsing — [Blink releases](https://github.com/1Axen/blink/releases)
- v1.0.0-pre.8 (2026-09-16): removed stale library options and bitpack attributes; fixes to player save creation, vector magnitude references, numeral bounds storage, example files — [Blink releases](https://github.com/1Axen/blink/releases)
- v1.0.0-pre.9 (2026-09-18): "Optimised Enum storage when the enum type is known at compile time"; "Disable write validations in `release` profile"; removed unimplemented CLI options (`--watch`, `--yes`); "Strip compiler comments (REMARK, bb etc.) outside of `test` profile"; generic type exports now error; fixes to enum validation, serialization errors, event consumption, player disconnection handling — [Blink v1.0.0-pre.9 release](https://github.com/1Axen/blink/releases/tag/v1.0.0-pre.9)
- v1.0.0-pre.10 (2026-09-19): added `@profile("...")` attribute for profile-based compilation gating; fixed NaN scalars/vectors bypassing inexact bounds validation; fixed exact vector length validation operator — [Blink releases](https://github.com/1Axen/blink/releases)

### Inferences
- On the 0.x line the Booleans and Entities hot paths (u8 writes, boolean writes, array length prefix, per-frame flush) have no listed changes since v0.17.1, so a v0.18.9 re-run should land close to the 2025 Blink numbers unless SyncValidation (default since v0.18.5) adds per-callback overhead on the receive side.
- On the 1.0 line, "Optimized array reads" (pre.6) targets exactly the receive path of `Entity[]`/`boolean[]`, and "Disable write validations in release profile" (pre.9) targets the send path; a `release`-profile 1.0 build is the configuration most likely to widen Blink's lead, while a default (validating) build may narrow it. The `bitpack` attributes removed in pre.8 suggest Blink experimented with, then dropped, explicit bitpacking during the 1.0 pre cycle; whether booleans are bitpacked in 1.0 by default is not stated.
- A faithful re-run should probably report both Blink 0.18.9 (same syntax, same option semantics as the 2025 run) and Blink 1.0.0-pre.10 (ported definition, stating which profile).

### Gaps
- Release notes on the HTML pages were summarized, not quoted; some minor items may be omitted. No Blink changelog file other than GitHub Releases was found.
- The exact semantics of Blink's compilation profiles (`release`/`debug`/`test`) and how to select them on the CLI were not fetched from the 1.0 docs.
- Whether Blink 0.17.1 or 0.18.9 bitpacks `boolean[]` was not verified from generated code.

## Q9. Are there newer third-party benchmarks (2025–2026) comparing Zap and Blink?

### Takeaway
Only one 2025 third-party comparison was found (a DevForum post in April 2025 using Zap 0.6.19 and Blink 0.17.0, concluding "blink is slightly better than zap"), plus an August 2024 GitHub repo that appears to be the model for 1Axen's harness. Nothing from 2026 was found.

### Cited Findings
- Eternity_Devs (khtsly), April 4, 2025, on the Packet library thread: tested ByteNet v0.4.3, Zap v0.6.19, Blink v0.17.0, Packet v1.2, NetRay v1.0.0; wrote that Packet "doesnt beating the other library (blink & zap) in bandwidth and fps mode, but it beat bytenet, netray & roblox" and that "blink is slightly better than zap"; NetRay produced "insane lags & studio crashes everywhere. data not sending"; attached `Benchmark.rbxl` (244.3 KB); referenced `nezuo/roblox-serde-benchmarks`; noted buffer size validation was removed from Packet to allow the test — [Packet thread reply #99](https://devforum.roblox.com/t/packet-networking-library/3573907/99)
- `nezuo/roblox-serde-benchmarks` (last updated August 16, 2024): compares Zap v0.6.12, ByteNet v0.4.6, Blink v0.14.6 and native Roblox in Studio; FPS read from the Ctrl+Shift+F5 menu and outgoing bandwidth from Ctrl+Shift+F3, with network tests firing once per second to isolate bandwidth from FPS; the author calls the numbers "eyeballed averages"; Booleans: Blink 71 FPS / 0.8 KB/s vs Roblox 19 FPS / 2100 KB/s; StructOfNumbers: Blink 38 FPS / 1.6 KB/s vs Roblox 6 FPS / 9500 KB/s; source in `src/` with `default.project.json`, place file built locally — [nezuo/roblox-serde-benchmarks](https://github.com/nezuo/roblox-serde-benchmarks)
- "Zap or ByteNet: Performance & Security" (DevForum Scripting Support, 2024) and "Zap or ByteNet Max?" (DevForum Code Review, 2025) discuss Zap vs ByteNet only; one reply characterizes Zap and ByteNet Max as "basically the same" — [Zap or ByteNet](https://devforum.roblox.com/t/zap-or-bytenet-performance-security/2888968/5); [Zap or ByteNet Max?](https://devforum.roblox.com/t/zap-or-bytenet-max/3820579/4)

### Inferences
- Both third-party efforts predate Zap v0.6.24 bitpacking and Blink 1.0, so none of the public numbers reflect the current state of either library; a fresh run is warranted.

### Gaps
- I did not capture nezuo's Zap or ByteNet figures (the fetch summary only returned Blink vs Roblox rows).
- No YouTube or 2026 GitHub benchmark comparing Zap and Blink surfaced in searches; absence of results is not proof none exist.
