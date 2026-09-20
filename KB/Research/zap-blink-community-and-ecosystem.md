---
type: research
date: 2026-09-20
session: 14e4b904
description: Developer sentiment, docs perceptions, tooling integration, adoption signals, bus factor, interop and runtime-safety findings for Zap and Blink as of 2026-09-20.
sources: [https://devforum.roblox.com/t/2959671, https://api.github.com/repos/red-blox/zap, https://api.github.com/repos/1Axen/blink, "KB/Library/community-and-ecosystem-notes.md"]
tags: [zap, blink, community, ecosystem]
---
# Zap and Blink: community, ecosystem and adoption signals
Up: [[Research]]

**Question:** What do developers say about the two, who uses them, and how safe are they to depend on?

**Answer:**
- **Sentiment:** no dedicated "Zap vs Blink" thread; comparisons surface inside broader "which network library" threads (2024 to 2025). Zap and ByteNet are treated as near-equivalent "safe picks"; Blink is recommended by a small set of vocal users as faster with a cleaner interface. The main complaint about Blink and IDL compilers generally is the regenerate-on-every-change workflow and learning a separate language.
- **Docs perception:** no post says "Zap's docs are better" in those words, but structurally Zap's site is broader (Options, Types, Functions, Generation pages plus a playground) while Blink's is ten pages with an acknowledged wrong snippet (May 2025), an open light-mode readability issue (Aug 2025) and a January 2026 request for video tutorials.
- **Tooling:** both slot into a Rojo project by emitting Luau modules. Zap has the more mature roblox-ts story (versioned `typescript` option), Aftman install, a playground, community Studio plugin (Zappy) and VS Code extension. Blink has the more modern install (Rokit, pesde, official Creator Store plugin) and a VS Code extension forked from Zap's; its TypeScript output exists in 0.18 but was a no-op in early 1.0 pre-releases. Blink credits Zap for its range and array syntax.
- **Adoption:** effectively tied on GitHub (Zap 187 stars / 29 forks; Blink 182 / 36); both on awesome-roblox. No "Used by" data, no notable open-source framework or template depends on either publicly. No game or studio publicly states it runs either at high CCU. Strongest indirect production evidence is on Zap's side: two 2026 issues from studios running forked builds in live games (#225 sharding fork; #219 servers "as old as several days" after a DoS fix).
- **Bus factor:** one for both. Zap is maintenance-only (rewrite dormant since July 2024, roughly one release per quarter from one maintainer, 2026 issues with zero comments). Blink is very active in September 2026 but single-author, with 19 open issues, several long-standing, and a visibly rough pre-release line.
- **Interop and lock-in:** no converter or migration guide in either direction. The IDLs are related and both emit server and client modules behind event handles, so migrating a small schema is a schema rewrite plus call-site renames, not game logic; Blink 1.0's attributes, profiles, imports and generics widen the gap over time.
- **Runtime safety:** both claim server-side validation of all received data, and both have open user-reported DoS issues where an oversized incoming buffer stalls or crashes the server (Blink #45, May 2025; Zap #219, March 2026). Neither docs site specifies decode-failure behaviour; Blink silently drops the rest of a batched packet with minimal logging (Sept 2026 issue). Blink shipped a NaN range-bypass fix on 2026-09-19; its 1.0 `release` profile strips write-side validation.

**Sources:** DevForum threads, GitHub API counts and issues, VS Code Marketplace, pesde; cited notes in [[Library/community-and-ecosystem-notes]] (2026-09-20).
**Confidence:** high for counts and quoted issues; medium for sentiment, which rests on a handful of DevForum voices. The Roblox OSS Discord, where Zap discussion lives, was not accessible.
**Applies to:** the from-scratch versus fork recommendation; the security posture in the design document; the distribution story (Rokit, pesde, plugin).
Related: [[Research/zap-0-6-current-state]] [[Research/blink-current-state]] [[Research/known-bugs-in-zap-and-blink]]
