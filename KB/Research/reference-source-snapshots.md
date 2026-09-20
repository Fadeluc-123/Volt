---
type: research
date: 2026-09-20
session: 14e4b904
description: What is in Reference/sources (Blink 0.18 compiler, Blink 1.0 rewrite, Zap 0.6.x emitters), how the files are laid out, and the rules for using them.
sources: [https://github.com/1Axen/blink/tree/main/src, https://github.com/1Axen/blink/tree/rewrite, https://github.com/red-blox/zap/tree/0.6.x/zap/src/output]
tags: [reference, blink, zap, source]
---
# Reference source snapshots in `Reference/sources/`
Up: [[Research]]

**Question:** What third-party source is available offline for design work, and how is it organised?

**Answer:** 176 files, about 1.25 MB, downloaded 2026-09-20 from GitHub and kept read-only at the repository root, outside the vault. **The folder is gitignored (ruled by Mike 2026-09-20)**: it exists only on the machine that fetched it, so a fresh clone will not have it. If it is missing, re-fetch: Blink 0.18 from `1Axen/blink` branch `main` (`src/` plus `test/`), Blink 1.0 from branch `rewrite` (every non-test `.luau`, flattened with underscores), Zap from `red-blox/zap` branch `0.6.x` (`zap/src/output/`), or download the tagged release matching the versions in [[Research/blink-current-state]] and [[Research/zap-0-6-current-state]]. Never edited, never restyled. Both projects are MIT.

- **`Reference/sources/blink-0.18/`** (main branch): `Lexer.luau`, `Parser.luau`, `Settings.luau`, `Builder.luau`, `CLI_init.luau`, `Compile.luau`, the three templates (`Base.luau`, `ClientTemplate.luau`, `ServerTemplate.luau`), the generator folder under `gen/` (`init.luau`, `Prefabs.luau`, `Blocks.luau`, `Util.luau`, `Typescript.luau`), `Test.blink`, and the mocked-remote test harness (`test_Shared.luau`, `test_Client.luau`, `test_Server.luau`). This is the primary architectural reference; [[Research/blink-0-18-compiler-pipeline]] is the reading guide.
- **`Reference/sources/blink-1.0-rewrite/`** (rewrite branch as of 2026-09-20): every non-test `.luau` file, 147 files, paths flattened with underscores (`compiler_lir_build_builders_ty_roblox_instance.luau` was `compiler/lir/build/builders/ty/roblox/instance.luau`). Also the `.lute` build scripts, `cli_init.luau`, `libs_*` helpers (fs, diagnostics, import resolver, result, panic) and `vendor_tiniest_*` (the test framework).
- **`Reference/sources/zap-0.6.x/`**: Zap's `zap/src/output/` tree: `luau_base.luau` (runtime template), `luau_client.rs`, `luau_server.rs`, `luau_mod.rs` (holds `push_remote_scope_validation`), `luau_types.rs`, `output_mod.rs`, `tooling.rs`, and `typescript_{client,server,mod,types}.rs`.

Not included: Blink's `benchmark/` folder (fetch fresh from GitHub, see [[Planning/volt-benchmark-plan]]), Zap's parser and IR (only the emitters were captured), and Zap's dormant `rewrite` branch (never read; a gap in [[Planning/volt-next-session-deliverables]]).

**Sources:** the GitHub trees above; bundle description in [[Library/handoff-2026-09-20]] section 12.
**Confidence:** high; file counts verified when the snapshot was moved into the repo on 2026-09-20.
**Applies to:** every design task that reads how Blink or Zap does something.
Related: [[Decisions/design-doc-before-code]] [[Research/blink-current-state]] [[Research/zap-0-6-current-state]]
