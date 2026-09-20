---
type: library
date: 2026-09-20
session: 14e4b904
title: Community and ecosystem (researcher notes)
origin: Research subagent, deep-research session ee3b949e, 2026-09-20
description: Researcher notes behind the report: eight questions on sentiment, docs perception, tooling, adoption, bus factor, interop and runtime safety.
tags: [zap, blink, networking, snapshot]
---
# Community adoption, developer sentiment, and ecosystem integration: Zap (red-blox/zap) vs Blink (1Axen/blink)
Up: [[Library]]

> Snapshot from 2026-09-20, kept verbatim for citations and detail. Current knowledge: [[Research/zap-blink-community-and-ecosystem]]. If they disagree with this document, they win.

Research date: 2026-09-20. All GitHub API numbers were fetched live on that date. DevForum quotes are reproduced verbatim from fetched pages; dates are given so the reader can judge staleness. Where a claim could not be sourced it is listed under Gaps rather than asserted.

Naming note: the Blink maintainer posts on the DevForum as "Ax3nx" and on GitHub as "1Axen". The Zap 0.6.x maintainer is "sasial-dev" on GitHub ("Sasial" in commit author fields); Zap's original author is "jackhexed"/jackdotink.

---

## Key Question 1: What do DevForum developers say when comparing Zap and Blink?

### Takeaway
There is no dedicated "Zap vs Blink" thread; the comparison surfaces inside broader "which network library" threads (2024–2025). The recurring pattern is: Zap and ByteNet are treated as near-equivalent and "the safe pick"; Blink is repeatedly recommended by a small set of vocal users as faster with a cleaner interface, while the main complaint about Blink (and IDL compilers generally) is the regenerate-on-every-change workflow and having to learn a separate language.

### Cited Findings
- Thread "Best Network library" (created May 27, 2025): TimeFrenzied wrote "I use Blink." and later "ByteNet/Max has CFrame issues for me, that's why I switched to blink" (post #25, May 27, 2025) and "Blink is more optimized and has a cleaner interface and completely fixes this problem" (post #37, May 28, 2025), adding "There are benchmarks (comparing to roblox, zap and bytenet) available on its devforum post btw" (post #41). — [Best Network library](https://devforum.roblox.com/t/best-network-library/3667044); [page 2](https://devforum.roblox.com/t/best-network-library/3667044?page=2)
- Same thread: thatguybarny1324 praised ByteNet Max for simplicity but called namespace setup annoying; no post in the thread argued *for* Zap specifically. — [Best Network library, page 2](https://devforum.roblox.com/t/best-network-library/3667044?page=2)
- Thread "Zap or ByteNet Max?" (created July 17, 2025): OP M_adpoint: "I've noticed a lot of developers recommending Zap as an alternative" and "both libraries offer fairly similar functionality, but it seems like Zap might be more actively maintained". Reply by westside216 (Aug 15, 2025): "Zap and ByteNet Max are both great modules, which yeah, as you said, basically are the same" and "I personally think Blink is a great networking module" and "According to their benchmarking, they're faster than ByteNet and Zap". OP later (Aug 16, 2025): "I haven't seen anything that Zap can do that ByteNet Max doesn't already offer". — [Zap or ByteNet Max?](https://devforum.roblox.com/t/zap-or-bytenet-max/3820579)
- Thread "Which network libraries do you use?" (created May 21, 2025): lavasance: "my go-to is zap, absolutely love it, and really useful", secondary choice Blink, noting "apparently blink is faster than zap". TimeFrenzied on Blink: "Code is generated based on your input, so it's better than most". D1CEL advised against adopting any library without profiling first. No poll in the thread. — [Which network libraries do you use?](https://devforum.roblox.com/t/which-network-libraries-do-you-use/3659422)
- Thread "Zap or ByteNet: Performance & Security" (created March 25, 2024): InfiniteYield argued buffers do not add security because "good exploiters can literally get into the lua registry and toy with any little system you put in"; xxWars_chick (Sep 7, 2024) later introduced Blink as a faster alternative to both; September 2025 replies emphasised avoiding premature optimization. — [Zap or ByteNet: Performance & Security](https://devforum.roblox.com/t/zap-or-bytenet-performance-security/2888968)
- Blink's own DevForum thread (created May 6, 2024; title currently shows 0.18.5; last reply Sep 21, 2025): Kilpamations (May 25, 2025): "if youre just starting I recommend using ByteNet because it doesnt require learning another language." and (May 30, 2025) "zap is mainly meant to be used in vscode and not roblox studio"; Kilpamations also asked for incremental updates: "it can get a little tedious having to generate new projects…"; 1xayd (Aug 13, 2025) complained of "lagginess of editor in studio after about 150 lines" in the Studio plugin. — [Blink thread page 4](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=4); [page 3](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=3)
- Blink thread page 1 (May 17, 2024): Riesegarder: "here I was despairing over Zap not having Studio drop in releases…" — an early adopter citing Blink's Studio plugin as the reason to pick it over Zap. — [Blink thread page 1](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671)
- Third-party benchmark in the "Packet" thread (Eternity_Devs, April 4, 2025, Zap 0.6.19 vs Blink 0.17.0): "blink & zap is the wins here…, but overall seems like blink is slightly better than zap(?)", with the caveat "my benchmark result may got different with yours". — [Packet thread post #99](https://devforum.roblox.com/t/packet-networking-library/3573907/99)
- Blink's own benchmark page (last updated April 30, 2025; Blink v0.17.1, Zap v0.6.20, ByteNet v0.4.3, Ryzen 9 7900X): Entities test median FPS Blink 42 / Zap 39 / ByteNet 32 / Roblox 16; bandwidth essentially identical (Blink 41.81 Kbps, Zap 41.71, ByteNet 41.64 vs Roblox 559,364); Booleans test FPS Blink 97 / Zap 52 / ByteNet 35 / Roblox 21. — [Blink Benchmarks.md](https://github.com/1Axen/blink/blob/main/benchmark/Benchmarks.md)

### Inferences
- The "Blink is faster" argument on the DevForum traces almost entirely back to Blink's self-published benchmark; the one independent benchmark found (Eternity_Devs) agrees but only calls the margin "slightly better". Bandwidth is a wash between the two.
- The DevForum voice arguing for Blink is concentrated in a few users (TimeFrenzied, westside216, xxWars_chick); Zap advocacy is thinner in text but Zap is more often the "default recommendation" people report hearing elsewhere ("a lot of developers recommending Zap").
- Zap's community discussion appears to live in the Roblox OSS Discord (per its README) rather than the DevForum, which biases DevForum-only sampling toward Blink.

### Gaps
- No official Zap DevForum release thread could be located via multiple searches; Zap's README points contributors to the "Roblox Open Source Software Community Discord" instead ([Zap README](https://github.com/red-blox/zap)). Discord content is not searchable here.
- No thread titled "Zap vs Blink" exists; all comparisons are incidental.
- No Reddit (r/robloxgamedev, r/roblox) discussion of either library surfaced in search; treat Reddit as an unknown rather than as silent.

---

## Key Question 2: Documentation quality perceptions

### Takeaway
No DevForum post was found that explicitly says "Zap's docs are better than Blink's." Structurally, Zap's docs site is broader (dedicated Options/Types/Functions/Generation pages plus a web playground) while Blink's site is ten pages; Blink's docs have had at least one acknowledged wrong snippet (May 2025) and an open readability issue (Aug 2025), and the 1.0 pre-release series is shipping features that are undocumented or non-functional.

### Cited Findings
- Zap's docs include separate pages for Options, Types, Functions, and "Generating Luau Code", and a web playground is offered as an installation path. — [Zap Options](https://zap.redblox.dev/config/options.html); [Zap Getting Started](https://zap.redblox.dev/intro/getting-started.html)
- Zap's own DX claims: an IDL that is "easy to learn" with "helpful error messages" and an API that is "fully typesafe" for Luau and TypeScript with "full type checking and autocompletion". — [What is Zap?](https://zap.redblox.dev/intro/what-is-zap.html)
- Blink's docs site navigation is: Getting Started (Installation, Introduction, Command-Line Usage, Roblox Studio Plugin) and Blink's Language (Options, Scopes, Imports, Types, Events, Functions) — ten pages total. — [Blink docs home](https://1axen.github.io/blink/)
- Context7's index of the Blink docs shows 58 snippets / 11,514 tokens and "Last Updated: 1 year ago" (as of 2026-09-20). — [Context7 Blink index](https://context7.com/websites/1axen_github_io_blink)
- Blink docs error acknowledged by the maintainer: TimeFrenzied (May 25, 2025): "Having a table inside of a struct seems to error…"; Ax3nx replied "The snippet on the docs had a mistake in it…". — [Blink thread page 3](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=3)
- Open Blink issue #60 (sooown, Aug 29, 2025, labels bug/documentation): "Code in docs hard to read (light mode)". — [Blink issues list](https://api.github.com/repos/1Axen/blink/issues?state=open&per_page=20&sort=created&direction=desc)
- Blink issue #99 (kaan650, Sep 15, 2026, closed) catalogued options in 1.0.0-pre.7 that "compile without warnings but lack implementation", including the `typescript` option, `--watch`, `--profile`, `@stable`, `@bitpack`, and inconsistent version strings (CLI banner "1.0.0", tag "1.0.0-pre.7", pesde.toml "0.1.0-pre.1"). — [Blink issue #99](https://github.com/1Axen/blink/issues/99)
- On the Zap side, v0.6.29 (June 23, 2026) release notes include "documentation updates for deprecated syntax". — [Zap releases](https://api.github.com/repos/red-blox/zap/releases?per_page=5)
- Kilpamations (May 25, 2025) framed the learning-curve complaint about IDL compilers generally: "if youre just starting I recommend using ByteNet because it doesnt require learning another language." — [Blink thread page 4](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=4)

### Inferences
- The user's perception that Zap's docs are clearer is consistent with the structural evidence (more pages, a playground, per-option version annotations like "[0.6.18+]"), but it is not something the community has articulated in a citable way.
- Blink's docs do not appear to have had a major overhaul in 2025–2026; the 1.0 pre-release features (profiles, attributes, generics, Lute dependency) are ahead of the documented surface, so a new adopter of Blink 1.0 would be reading release notes and issues rather than docs.

### Gaps
- No direct developer quote comparing the two docs sites was found.
- Could not confirm whether the Blink docs pages themselves were updated for the 1.0 pre-releases (the Context7 "1 year ago" stamp is an indirect signal only).

---

## Key Question 3: Ecosystem and tooling integration

### Takeaway
Both are CLI code generators that slot into a Rojo project by emitting Luau modules to configured paths. Zap has the more mature roblox-ts story (a documented, versioned `typescript` option generating `.d.ts`), plus Aftman install, a web playground, a community Studio plugin (Zappy), and a community VS Code extension. Blink has the more modern install story (Rokit recommended, pesde package, official Studio plugin on the Creator Store) and a VS Code extension that is itself a fork of the Zap one; its TypeScript output exists in 0.18.x but was a no-op in early 1.0 pre-releases.

### Cited Findings
- Zap install paths: GitHub Releases, `aftman add red-blox/zap`, "the community-made Zappy" Studio plugin, and a web playground. Rokit, npm, Wally, and Lune are not mentioned on the page. — [Zap Getting Started](https://zap.redblox.dev/intro/getting-started.html)
- Zap options relevant to Rojo/roblox-ts: `server_output`, `client_output`, `types_output` [0.6.18+], `tooling_output`; `typescript` (default false) "Determines if Zap should generate TypeScript definition files alongside generated Luau code"; `typescript_max_tuple_length` (default 10); `typescript_enum` [0.6.24+] with `StringLiteral` / `ConstEnum` / `StringConstEnum`; `yield_type` (`yield` / `future` / `promise`) with `async_lib`; `tooling` (default false) "Determines if Zap should generate a file to allow it to interface with other tooling". — [Zap Options](https://zap.redblox.dev/config/options.html)
- Zap docs state the generated `.d.ts` files use "the same paths as the generated Luau server and client". — [Zap Options (via search)](https://zap.redblox.dev/config/options.html)
- Zap v0.6.29 (June 23, 2026) "Allow Requiring Zap from Edit Mode (#218)" was contributed by EstebenR to make Storybook/UI-story tooling work when components require the client module in edit mode. — [Zap commits](https://api.github.com/repos/red-blox/zap/commits?per_page=5)
- Blink install paths: "The recommended way to install blink is using Rokit" (`rokit add 1Axen/blink`); pre-built binaries from GitHub Releases; "An official release is available on pesde starting from version 0.18.5" (`pesde add --dev 1axen/blink`); and "Blink offers a companion studio plugin which allows you to write and generate files within Studio without the need for external tooling", available on the Creator Store. Aftman, npm, Wally, Lune, GitHub Actions and VS Code are not mentioned. — [Blink Installation](https://1axen.github.io/blink/getting-started/1-installation)
- Blink repo contains a `rokit.toml`, i.e. the project itself is developed with Rokit. — [blink/rokit.toml](https://github.com/1Axen/blink/blob/main/rokit.toml)
- Blink open issue #81 (oryaelia, Apr 6, 2026): "NOOP should support Blink in stories" — the same UI-story/edit-mode need Zap addressed in #218. — [Blink issues list](https://api.github.com/repos/1Axen/blink/issues?state=open&per_page=20&sort=created&direction=desc)
- VS Code: `zap-vscode` by tijnepema, "Syntax highlighting and intellisense for the Zap IDL". — [tijnepema/zap-vscode](https://github.com/tijnepema/zap-vscode)
- VS Code: `blink-vscode` by checkraisefold on Open VSX, described as providing intellisense and highlighting for the Blink IDL and "a fork of zap-vscode". — [Open VSX blink-vscode](https://open-vsx.org/extension/checkraisefold/blink-vscode)
- Blink TypeScript output: the releases page records a fix for "TypeScript codegen outputting field: type | undefined, instead of field?: type" for optional types (0.18.x era). — [Blink releases](https://github.com/1Axen/Blink/releases)
- In Blink 1.0.0-pre.7, the `typescript` option "accepts boolean input but generates no `.d.ts` output" (issue #99, closed). — [Blink issue #99](https://github.com/1Axen/blink/issues/99)
- Blink Studio plugin pain points: open issue #12 (riesegarder, July 2, 2024, 5 comments) "Plugin lags with larger config files" (lag with a 191-line config); #29 "Cannot undo deleting config file"; #20 "Plugin should respect Output options". — [Blink issues list](https://api.github.com/repos/1Axen/blink/issues?state=open&per_page=20&sort=created&direction=desc)
- Blink generated-source size limit hit in Studio: bossagec (Nov 7, 2024) reported "Unable to assign property Source. Provided string…" (204,873 vs 200,000 char limit); Ax3nx: "Not much you can do, needs to be solved on my end". — [Blink thread page 3](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=3)
- Zap's repository shows Rust (Cargo.toml) plus package.json/bun.lock, i.e. the compiler is Rust and there is an npm/JS surface in the repo. — [red-blox/zap](https://github.com/red-blox/zap)
- Blink 1.0.0-pre.7 (Aug 24, 2026) "Upgraded lute dependency to 1.0.0" — Blink 1.0 is built on Lute (a Luau runtime). — [Blink releases API](https://api.github.com/repos/1Axen/blink/releases?per_page=5)
- Both Zap and Blink are listed in the awesome-roblox curated list alongside ByteNet, RbxNet and Red. — [awesome-roblox](https://github.com/awesome-roblox/awesome-roblox)

### Inferences
- For a Rojo + roblox-ts project, Zap is the cleaner fit today: the TS option is documented, versioned, and has tunables (`typescript_enum`, tuple length); Blink's TS output is real in 0.18.x but was broken in the first 1.0 pre-releases and is undocumented on the docs site.
- For a Rojo + Luau project, the two are close; Blink's Rokit/pesde-first install and official Studio plugin are more modern conveniences, whereas Zap's docs still say Aftman (though Rokit can install any GitHub-release tool, this is unverified for Zap specifically).
- Zap's `tooling` option and `types_output` suggest more thought toward third-party integrations (debug tooling, shared types) than Blink currently documents.

### Gaps
- Could not verify a `rokit add red-blox/zap` path from Zap's own docs (only Aftman is documented).
- Neither library was found in a Wally index (both are CLIs, not runtime packages); not confirmed either way.
- No official Lune scripts, GitHub Actions workflows, or Luau LSP-specific integration docs were found for either project.
- No roblox-ts/Flamework template repository using either Zap or Blink was found; Flamework ships its own `@flamework/networking`, and the awesome-roblox-ts list was not confirmed to mention either tool.

---

## Key Question 4: Adoption signals (stars, dependents, notable users)

### Takeaway
On raw GitHub numbers the two are effectively tied (Zap 187 stars / 29 forks; Blink 182 stars / 36 forks as of 2026-09-20), and both are on the awesome-roblox list. No "Used by" dependents data, no notable open-source framework, and no popular template was found that publicly depends on either.

### Cited Findings
- Zap (fetched 2026-09-20): 187 stars, 29 forks, 7 subscribers, 9 open issues, created 2023-12-14, default branch `0.6.x`, MIT, not archived. — [GitHub API red-blox/zap](https://api.github.com/repos/red-blox/zap)
- Blink (fetched 2026-09-20): 182 stars, 36 forks, 3 subscribers, 20 open issues+PRs (19 issues, 1 PR), created 2023-12-24, default branch `main`, MIT, not archived. — [GitHub API 1Axen/blink](https://api.github.com/repos/1Axen/blink); [1Axen/blink](https://github.com/1Axen/blink)
- Blink's README: "Credits to Zap for the range and array syntax". — [1Axen/blink](https://github.com/1Axen/blink)
- Public forks of Zap exist (e.g. Ezzenix/zap), and issue #225 states a studio maintains a sharding fork for "larger games". — [Ezzenix/zap](https://github.com/Ezzenix/zap); [Zap issue #225](https://github.com/red-blox/zap/issues/225)
- Both projects appear in the awesome-roblox curated list. — [awesome-roblox](https://github.com/awesome-roblox/awesome-roblox)
- A for-hire scripter portfolio (EnumEnv, "7+ years") lists Blink Networking among tools used. — [EnumEnv portfolio](https://devforum.roblox.com/t/enumenv-experienced-scripter-for-hire/4089433)
- Zap's 0.6.x line has received outside contributions (EstebenR's #218 in May 2026; dependabot PRs), whereas the five most recent Blink commits are all by 1Axen. — [Zap commits](https://api.github.com/repos/red-blox/zap/commits?per_page=5); [Blink commits](https://api.github.com/repos/1Axen/blink/commits?per_page=5)

### Inferences
- Star counts this close mean stars are not a useful tie-breaker; the more meaningful adoption signals are the existence of production forks of Zap (implying larger games depend on it) and Blink's steady stream of user-filed issues in 2026.
- Blink's 36 forks vs Zap's 29 may partly reflect Blink being Luau/Lute-based (easier for Roblox devs to fork) versus Zap being Rust.

### Gaps
- GitHub "Used by" dependents were not available for either repo (neither publishes a package manifest that GitHub tracks).
- No ECS (Jecs/Matter) examples, Flamework integrations, or named frameworks (Centauri, Sapphire, Prvdmwrong) were found referencing either library; treat as unverified rather than absent.
- The GitHub star numbers above are exactly as the API returned them on 2026-09-20; the report writer may wish to re-check, since they are lower than one might expect for tools this widely discussed.

---

## Key Question 5: Maintenance and bus-factor signals

### Takeaway
Zap is in a "maintenance-only" state: the rewrite branch has been dormant since July 2024, the shipping 0.6.x line is kept alive by a single maintainer (sasial-dev) with roughly one release per quarter and several 2026 issues sitting with zero comments. Blink is very active in September 2026 (stable 0.18.9 and a rapid 1.0 pre-release series) but is a single-author project with 19 open issues, several long-standing (2024–2025) unanswered ones, and a pre-release line that is visibly rough.

### Cited Findings
- Zap README: "Zap is currently undergoing a rewrite, which can be found at the rewrite branch, while versions `0.6.x` are being maintained by @sasial-dev, on the 0.6.x branch." — [red-blox/zap](https://github.com/red-blox/zap)
- Zap rewrite branch: most recent commits are by jackhexed on 2024-07-07 ("make CI run for all PRs") and 2024-06-11; the rewrite README says "Zap is currently in a early pre-release state. The API may change over time and there are likely bugs." — [Zap rewrite commits](https://api.github.com/repos/red-blox/zap/commits?sha=rewrite&per_page=5); [rewrite README](https://github.com/red-blox/Zap/blob/rewrite/README.md)
- Zap 0.6.x releases: v0.6.29 (2026-06-23), v0.6.28 (2025-12-13), v0.6.27 (2025-10-05), v0.6.26 (2025-09-28), v0.6.25 (2025-07-21); all published via github-actions. Latest push to the repo: 2026-06-23. — [Zap releases API](https://api.github.com/repos/red-blox/zap/releases?per_page=5); [GitHub API red-blox/zap](https://api.github.com/repos/red-blox/zap)
- Zap open issues with zero comments as of 2026-09-20 include #225 (2026-09-10), #224 (2026-07-14), #216 (2026-01-08, "Player memory leaked if Fire called after removal"), #211 (2025-10-26), #196 (2025-06-11); #219 (2026-03-25) has 3 comments; #72 and #67 date from Feb 2024. — [Zap issues API](https://api.github.com/repos/red-blox/zap/issues?state=open&per_page=15&sort=created&direction=desc)
- Zap issue #225 (InfiniteYield, Sep 10, 2026, open, no comments): "the generated modules are so big they can't even get past bytecode generation before tripping the Roblox script execution timeout error"; the studio runs a fork and proposes an `opt max_events_per_file` option. — [Zap issue #225](https://github.com/red-blox/zap/issues/225)
- Blink: five most recent commits all authored by 1Axen; latest 2026-09-19 ("v0.18.9", "fix NaN scalars and vectors bypassing range validation"); previous stable activity 2026-04-11 (0.18.8). Repo pushed_at 2026-09-19. — [Blink commits](https://api.github.com/repos/1Axen/blink/commits?per_page=5); [GitHub API 1Axen/blink](https://api.github.com/repos/1Axen/blink)
- Blink releases: v1.0.0-pre.10 (2026-09-19), v0.18.9 (2026-09-19, stable), v1.0.0-pre.9 (2026-09-18), v1.0.0-pre.8 (2026-09-16), v1.0.0-pre.7 (2026-08-24); all by 1Axen. — [Blink releases API](https://api.github.com/repos/1Axen/blink/releases?per_page=5)
- Blink open issues: ten filed by kaan650 on 2026-09-15 with the "rewrite" label (#101–#109) plus #111 by 1Axen (thread pool for Many* events); #45 "Server DOS via large buffer input" (May 22, 2025, 1 comment, still open); #12 plugin lag (July 2024, still open); #29 (Nov 2024); #20 (Oct 2024). — [Blink issues API](https://api.github.com/repos/1Axen/blink/issues?state=open&per_page=20&sort=created&direction=desc)
- Blink 1.0 pre.7 bug cluster reported Sept 2026: #92 "players_map is only populated by PlayerAdded: players present before the server module loads break reliable fires", #93 "Messages received before on() is connected are silently dropped and the internal queue grows forever", #94 "vector(range) crashes at runtime", #98 "examples/generics.blink does not compile". — [#92](https://github.com/1Axen/blink/issues/92); [#93](https://github.com/1Axen/blink/issues/93); [#94](https://github.com/1Axen/blink/issues/94); [#98](https://github.com/1Axen/blink/issues/98)
- Blink issue #99 was filed 2026-09-15 and is closed, and pre.8/pre.9/pre.10 shipped 2026-09-16/18/19 — the maintainer turned around that batch within days. — [Blink issue #99](https://github.com/1Axen/blink/issues/99); [Blink releases API](https://api.github.com/repos/1Axen/blink/releases?per_page=5)
- Blink's DevForum thread: last reply Sep 21, 2025, with the maintainer (Ax3nx) still answering support questions through that date. — [Blink thread page 4](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=4)
- Earlier DevForum perception (July 2025): "it seems like Zap might be more actively maintained" (M_adpoint, comparing to ByteNet Max, not Blink). — [Zap or ByteNet Max?](https://devforum.roblox.com/t/zap-or-bytenet-max/3820579)

### Inferences
- Zap's bus factor is effectively one (sasial-dev) for the only usable line, and the "rewrite" that the README advertises has not moved in over two years; a reader should treat 0.6.x as the product and not expect a next-gen Zap.
- Blink's bus factor is also one (1Axen), but the maintainer is demonstrably active in September 2026. The risk with Blink is different: a fast-moving 1.0 pre-release with known validation regressions, versus Zap's slow-but-stable 0.6.x.
- Neither project has posted a "looking for maintainers" notice; none was found.

### Gaps
- No public statement from jackdotink/jackhexed about the future of the Zap rewrite was found.
- Could not determine median issue response time quantitatively; only the anecdotal pattern above (Zap: many zero-comment issues; Blink: fast turnaround on maintainer-prioritised issues, slow on plugin/DoS issues).

---

## Key Question 6: Interop and lock-in (IDL similarity, generated API shape, converters)

### Takeaway
No converter or migration guide in either direction was found. The IDLs are related (Blink explicitly credits Zap for range/array syntax) and both generate server/client Luau modules, so a hand migration is plausible for simple schemas, but Blink 1.0 is adding attributes, profiles, imports, and generics that have no Zap equivalent, increasing divergence over time.

### Cited Findings
- "Credits to Zap for the range and array syntax" — [1Axen/blink README](https://github.com/1Axen/blink)
- Blink docs describe an IDL with Options, Scopes, Imports, Types, Events, Functions; Zap docs describe Options, Types, Functions, and generation. — [Blink docs](https://1axen.github.io/blink/); [Zap Options](https://zap.redblox.dev/config/options.html)
- Blink 1.0 pre-release syntax additions: `@profile("...")` attribute (pre.10), `@export` (the only attribute that "properly functions" in pre.7), `@stable`/`@bitpack`/`@target` (accepted but no-ops in pre.7), `from`/`as` keyword parsing fixes (pre.7), and an `examples/generics.blink` file. — [Blink releases API](https://api.github.com/repos/1Axen/blink/releases?per_page=5); [Blink issue #99](https://github.com/1Axen/blink/issues/99); [Blink issue #98](https://github.com/1Axen/blink/issues/98)
- Zap's generated API shape is configurable via `casing` (`PascalCase` default, `camelCase`, `snake_case`) and `call_default`; remotes are named via `remote_scope` (default `ZAP`, creating `ZAP_RELIABLE` / `ZAP_UNRELIABLE`) in a `remote_folder` under ReplicatedStorage. — [Zap Options](https://zap.redblox.dev/config/options.html)
- Zap v0.6.28 (Dec 13, 2025) changed "Reliable" to the default event type. — [Zap releases API](https://api.github.com/repos/red-blox/zap/releases?per_page=5)
- Blink's VS Code extension is a fork of Zap's, indicating enough grammar overlap that one tokenizer could be adapted for the other. — [Open VSX blink-vscode](https://open-vsx.org/extension/checkraisefold/blink-vscode)
- Migration anecdotes found on the DevForum go ByteNet -> Blink (TimeFrenzied, May 2025), not Zap <-> Blink. — [Best Network library page 2](https://devforum.roblox.com/t/best-network-library/3667044?page=2)

### Inferences
- Because both compilers emit the networking layer as generated modules that the rest of the game calls through event handles, the practical migration cost is rewriting the schema file plus the call-site names/casing, not rewriting game logic. This is a moderate, mechanical cost for small schemas and a real cost for large ones (see the >200 KB generated-source reports on both sides).
- Lock-in risk is asymmetric: Zap 0.6.x's IDL is frozen, so a schema written today will still compile in a year; Blink's 1.0 IDL is still changing.

### Gaps
- No Zap<->Blink converter, script, or migration write-up exists in any source found.
- No developer account of migrating specifically from Zap to Blink or Blink to Zap was found.

---

## Key Question 7: Runtime safety against malformed or malicious packets

### Takeaway
Both projects claim server-side validation of all received data, and both have open, user-reported denial-of-service issues where a client sending an oversized buffer can stall or crash the server (Blink #45, May 2025, still open; Zap #219, March 2026, open). Neither docs site specifies what happens on decode failure; Blink's current behaviour (per a Sept 2026 issue) is to silently drop the rest of the batched packet with minimal logging. Blink's stable line shipped a NaN range-validation bypass fix on 2026-09-19, and its 1.0 pre-releases strip write-side validation in the release profile.

### Cited Findings
- Zap docs: "Zap is fully secure"; Zap "validates all data recieved"; "If a client sends invalid data, Zap will catch it before it reaches your game code." The page does not say whether invalid data errors, is dropped, or kicks the client. — [What is Zap?](https://zap.redblox.dev/intro/what-is-zap.html)
- Zap `write_checks` (default `true`): "Determines if Zap should check types when writing data to the network" — these are write-side (sender) checks for constraints Luau cannot verify statically. Zap "only checks types that cannot be statically checked by Luau or TypeScript … it will check that the string is 20 characters long". — [Zap Options](https://zap.redblox.dev/config/options.html)
- Zap issue #219 (CoIorEvent8, Mar 25, 2026, open, "enhancement"): describes exploiters sending oversized buffer payloads repeatedly so the server "enters constant processing loops without yielding", exhausting memory and crashing servers; the reporter bypassed the 256-call-limit error and, after patching a custom build with throughput mediation, went from "30 minute sessions back to having servers as old as several days". No maintainer response was visible in the fetched issue body. — [Zap issue #219](https://github.com/red-blox/zap/issues/219)
- Zap v0.6.27 (Oct 5, 2025) "fixes a rare bug where you could get a buffer access out of bounds error if you had more than 256 concurrent function calls"; v0.6.25 (Jul 21, 2025) "Fix bitpacking mismatch". — [Zap releases API](https://api.github.com/repos/red-blox/zap/releases?per_page=5)
- Zap open issue #216 (dev-alastair, Jan 8, 2026, 0 comments): "`Player` memory leaked if `Fire` called after removal". — [Zap issues API](https://api.github.com/repos/red-blox/zap/issues?state=open&per_page=15&sort=created&direction=desc)
- Blink docs: "data sent by clients will be validated on the receiving side before reaching any critical game code" and compression makes it "significantly harder to snoop on your game's network traffic". — [Blink docs home](https://1axen.github.io/blink/); [1Axen/blink](https://github.com/1Axen/blink)
- Blink issue #45 (author "ghost", May 22, 2025, open, no labels): if a client sends e.g. `buffer.create(1000000)`, the server "attempts to parse the entire buffer within a loop", risking severe slowdown or crash. No maintainer response visible. — [Blink issue #45](https://github.com/1Axen/blink/issues/45)
- Blink issue #102 (kaan650, Sep 15, 2026, open, labels enhancement/rewrite): current receive loop on decode failure "Silently drops remaining batched events from that packet" with "minimal logging with no player identification or event context", making rate-limiting and kicking impossible; requests `net.on_error(player, name, err)` and an `on_invalid = "drop" | "kick" | "error"` option. — [Blink issue #102](https://github.com/1Axen/blink/issues/102)
- Blink v0.18.9 (Sep 19, 2026, stable): "resolved an issue where NaN values were circumventing inexact range validation checks on floating-point and vector types"; commit "fix NaN scalars and vectors bypassing range validation". — [Blink releases API](https://api.github.com/repos/1Axen/blink/releases?per_page=5); [Blink commits](https://api.github.com/repos/1Axen/blink/commits?per_page=5)
- Blink v1.0.0-pre.9 (Sep 18, 2026): "Disabled write validations in release profile" and fixed "enum type validation, read validation, and event-handling issues"; related design issue #110 "Make compile profiles meaningful: release strips write-side validation, debug keeps names and traces". — [Blink releases API](https://api.github.com/repos/1Axen/blink/releases?per_page=5); [Blink issue #110](https://github.com/1Axen/blink/issues/110)
- Blink 0.18.x had a `WriteValidations` option to turn off validation for production; that option is absent in 1.0.0-pre.7 (superseded by profiles). — [Blink issue #99 (via search)](https://github.com/1Axen/blink/issues/99)
- Blink 1.0 pre-release validation regressions reported Sept 2026: #90 "Numeric ranges (e.g. u8(0..10)) are parsed but never enforced"; #91 "A validation error inside fire() leaves partial bytes in the outgoing buffer and corrupts the batch"; #95 "Self-recursive struct validation" (bug). — [#90](https://github.com/1Axen/blink/issues/90); [#91](https://github.com/1Axen/blink/issues/91); [Blink issues API](https://api.github.com/repos/1Axen/blink/issues?state=open&per_page=20&sort=created&direction=desc)
- Blink has a `SyncValidation` option that "when enabled, will emit code that checks for yielding in Sync callbacks"; the maintainer pointed a user to it on Sep 21, 2025. — [Blink releases](https://github.com/1Axen/Blink/releases); [Blink thread page 4](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=4)
- Blink open issue #88 (ccrossedheart, Jun 15, 2026): "Omit sent instance table if empty" — indicates Blink sends Instance references via a side table separate from the buffer. — [Blink issues API](https://api.github.com/repos/1Axen/blink/issues?state=open&per_page=20&sort=created&direction=desc)
- Skeptical community view (2024): buffers do not add real security because exploiters can hook the client anyway (InfiniteYield). — [Zap or ByteNet: Performance & Security](https://devforum.roblox.com/t/zap-or-bytenet-performance-security/2888968)

### Inferences
- The oversized-buffer DoS is a shared class of problem: both compilers trust the incoming buffer length and iterate over it on the server. Zap's #219 reporter demonstrated real crashes in production; Blink's #45 is a theoretical report that has sat unanswered for 16 months. A new project on either should plan its own per-player packet-size/rate guard at the RemoteEvent boundary.
- Blink's maintainer is actively hardening validation (NaN fix shipped same day as pre.10), but the 1.0 pre-release line is where the regressions are; the 0.18.x stable line is the safer Blink today.
- Neither project documents an "on invalid data" policy; Blink's is at least now spelled out in an issue (silent drop), Zap's remains unspecified in docs.

### Gaps
- No developer report of an actual exploit-driven crash with Blink was found (only the theoretical #45); no confirmation of how Zap handles decode failure (error vs drop) beyond the docs claim.
- Instance sanitization details (what happens when a client sends an Instance of the wrong class, or a destroyed Instance) were not found in either docs site; Blink has a related open bug #75 "Cannot specify instance class with numbers" (Jan 4, 2026).

---

## Key Question 8: Production-scale usage (high-CCU games publicly using either)

### Takeaway
No game or studio was found publicly stating it runs Zap or Blink at high CCU. The strongest indirect evidence of production scale is on the Zap side: two 2026 issues from studios running forked builds in live games ("larger games" needing module sharding; servers "as old as several days" after a DoS fix).

### Cited Findings
- Zap issue #225 (Sep 10, 2026): a studio states the generated modules exceed Roblox bytecode limits "for larger games" and that they maintain a fork with sharding. — [Zap issue #225](https://github.com/red-blox/zap/issues/225)
- Zap issue #219 (Mar 25, 2026): reporter runs a patched build in production and cites server uptimes improving to "several days". — [Zap issue #219](https://github.com/red-blox/zap/issues/219)
- Blink DevForum thread (Nov 7, 2024): a user hit the 200,000-character Studio source limit with their generated module, implying a large event schema in use. — [Blink thread page 3](https://devforum.roblox.com/t/blink-an-idl-compiler-written-in-luau-for-roblox-buffer-networking-0185/2959671?page=3)
- EnumEnv, a for-hire scripter, lists Blink Networking among their tools (2026 portfolio). — [EnumEnv portfolio](https://devforum.roblox.com/t/enumenv-experienced-scripter-for-hire/4089433)

### Inferences
- The existence of production forks of Zap (with the same problems recurring across studios) suggests Zap is in real large-game use even though nobody names the games.
- Blink's issue tracker in 2026 is dominated by a single power user (kaan650) stress-testing the 1.0 pre-release, which reads more like an evaluation than a fleet of production deployments.

### Gaps
- No public "we use Zap/Blink" statement from any named high-CCU game was found on the DevForum, GitHub, or blogs.
- No YouTube tutorials comparing the two surfaced in search (queries returned only GitHub/DevForum results).
- No 2024–2026 blog posts by Roblox developers comparing the two were found.
