---
type: standard
date: 2026-09-20
session: 14e4b904
description: Mike's ratified Luau style guide, split one node per section; all code must be indistinguishable from his, and these nodes override anything that contradicts them.
tags: [code-style, luau, index]
---
# Code style: overview and section map
Up: [[Standards]]

**Rule:** All Luau written for Volt is indistinguishable from Mike's own code. The `code-style-*` nodes are law, not guidance; they override anything elsewhere that contradicts them, and a diff that breaks them is sent back.

**Why:** A codebase built by many agents must read as one author's work. Style is the review gate that keeps it so.

**How to apply:**
- Read [[Standards/code-style-sixty-second-version]] first, every time. It is the short list of the fastest tells plus the ratified rules that override everything else. Then open the section the work touches.
- Provenance: ratified by Mike 2026-07-29, derived from seven of his codebases in precedence order `redfallOld` (best, most recent) then `oakshire` (production), `scrap`, `menu`, `travelers` and `zombie` (commissions), and last `dawn` (old, poor standards; historical context only, never adopt). Amended 2026-08-25 (framework settled as Knit; sections 1, 4, 7, 8, 9, 11, 12 and 14), 2026-08-26 (sections 0, 2, 5: a comment never records a decision; file header cut to four or five lines at eighty columns), and 2026-08-31 to 2026-09-02 (type-annotation rulings in section 3, `string.format` allowed in 6.3).
- Anything marked **LEGACY, do not write** appears only in older repos. It is documented so old code can be read, never reproduced.
- Section numbers are preserved exactly because other notes cite them (`§8.6`, `§10.2`, `§11.3`).
- The guide was written for Mike's Knit game codebase (Frontier Zero, formerly Redfall). Volt is a networking package whose wrapper is meant to replace Knit, so sections 8, 9 and 10 describe the consumer-side shape Volt must fit and the conventions its wrapper inherits; everything else applies to Volt's own code directly.

| Section | Node | Covers |
|---|---|---|
| 0, 0.1 | [[Standards/code-style-sixty-second-version]] | The fastest tells and the ratified rules |
| 1 | [[Standards/code-style-file-and-folder-naming]] | Casing, `init.lua`, the folder taxonomy |
| 2 | [[Standards/code-style-script-headers-and-doc-comments]] | The file header template, doc-comments, header hygiene |
| 3 | [[Standards/code-style-strict-mode-and-types]] | `--!strict`, the `Config/Types` pattern, annotation style |
| 4 | [[Standards/code-style-internal-script-layout]] | Block order, function order, public vs private, spacing |
| 5 | [[Standards/code-style-comments-and-voice]] | Inline comments, TODO markers, voice, no decisions in comments |
| 6 | [[Standards/code-style-formatting]] | StyLua config, strings, control flow, error convention, Promises, `_G` ban |
| 7 | [[Standards/code-style-module-and-class-patterns]] | The four module shapes, Actions/Functions/Adapters, pub/sub |
| 8 | [[Standards/code-style-knit-service-layout]] | Service and controller skeleton, lifecycle, bootstrap, components, cleanup |
| 9 | [[Standards/code-style-client-server-communication]] | Knit transport, Policy pipeline, payload discipline, server authority, snapshot/patch |
| 10 | [[Standards/code-style-react-ui-conventions]] | React stack, directory contract, components, hooks, mounting, animation |
| 11 | [[Standards/code-style-tooling-config-conventions]] | Rojo, Aftman, Wally, selene, StyLua, editor, git |
| 12 | [[Standards/code-style-evolution-notes]] | Where current code departs from older code |
| 13 | [[Standards/code-style-do-not-copy-list]] | Shipped defects that are never reproduced |
| 14 | [[Standards/code-style-new-file-checklist]] | What every new file satisfies before it is written |

**Exceptions:** Vendored packages (`Modules/Libraries/`, Wally `Packages/`) are never restyled. When editing an existing file in an old repo, match that file rather than reformatting it.
Related: [[Standards/code-style-sixty-second-version]] [[Standards/working-with-mike]]
