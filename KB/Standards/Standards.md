---
type: path
description: Conventions and rules for how work on Volt is done. Read in full at every session start.
---
# Standards
Up: [[Core]]

One node per convention. A standard is a rule that can be followed without interpretation: naming, structure, process, tooling, what is never done. If a rule is worth repeating to the next session, it belongs here.

**Read at session start:** always, in full (injected by the SessionStart hook).

## When to add a node

When the user states a preference or rule, when a decision is made that future sessions must respect, or when a Mistakes node produces a rule general enough to stand on its own. If a standard changes, edit the node and note the date of the change in it. Do not create a second node for a revised rule.

## Node template

File name: a short kebab-case slug that names the rule, for example `git-commits-are-manual.md`.

```md
---
type: standard
date: YYYY-MM-DD
session: <first 8 chars of session id>
description: <one line: the rule>
tags: []
---
# <Rule, one line>
Up: [[Standards]]

**Rule:** the convention, stated so it can be followed without interpretation.
**Why:** the reason it exists.
**How to apply:** concrete guidance or examples.
**Exceptions:** none, or the exact cases.
Related: [[Mistakes/...]]
```

## Nodes
<!-- kb:auto-start -->
- [[Standards/address-mike-in-every-message|Every message to the user is addressed to Mike]] - Every message to the user opens by addressing him as Mike; a message that does not is an early sign of context rot.
- [[Standards/code-style-client-server-communication|Code style §9: client-server communication]] - Code style section 9: Knit is the only transport, the Policy inbound pipeline (rate limit, guards, schema), the Service.Client wrapper, payload discipline, the nine-layer server-authority stack, snapshot/patch replication, and client-internal decoupling.
- [[Standards/code-style-comments-and-voice|Code style §5: comment structure, density and voice]] - Code style section 5: comment density and shape, no magic arguments, the Whiteoak TODO and FIXME markers, Mike's voice, and the rule that a comment never records a decision.
- [[Standards/code-style-do-not-copy-list|Code style §13: the do-not-copy list]] - Code style section 13: shapes that appear in Mike's shipped code but are defects, never reproduced.
- [[Standards/code-style-evolution-notes|Code style §12: evolution notes, where newer code departs]] - Code style section 12: the table of where current code (redfallOld, oakshire) departs from older repos; always write the Current column, and never cite dawn as precedent.
- [[Standards/code-style-file-and-folder-naming|Code style §1: file and folder naming]] - Code style section 1: exact casing rules, the init.lua folder-module pattern, and the canonical folder taxonomy including where config, extensions and vendored code live.
- [[Standards/code-style-formatting|Code style §6: formatting]] - Code style section 6: the stylua.toml config and how formatting is run, line width, quotes and interpolation, numbers and operators, control-flow shapes, the (boolean, string | nil) error convention, yielding returns a Promise, and the _G ban.
- [[Standards/code-style-internal-script-layout|Code style §4: internal script layout order]] - Code style section 4: the exact block order inside a script, function ordering, the public/private naming table with reserved verbs, and the blank-line rules.
- [[Standards/code-style-knit-service-layout|Code style §8: Knit service and controller layout]] - Code style section 8: thin Knit services and controllers, the exact service table skeleton, KnitInit/KnitStart usage, the twin bootstraps with Policy.apply, sleitnick Components, and the connection-hygiene review gate.
- [[Standards/code-style-module-and-class-patterns|Code style §7: module and class patterns]] - Code style section 7: the only four module shapes (metatable class, singleton table, single-function module, builder DSL), the Actions/Functions/Adapters decomposition, and the pub/sub idiom with the empty-table token.
- [[Standards/code-style-new-file-checklist|Code style §14: the new-file checklist]] - Code style section 14: the annotated skeleton every new file follows and the pre-PR checklist against the ratified rules.
- [[Standards/code-style-overview|Code style: overview and section map]] - Mike's ratified Luau style guide, split one node per section; all code must be indistinguishable from his, and these nodes override anything that contradicts them.
- [[Standards/code-style-react-ui-conventions|Code style §10: React (jsdotlua) UI conventions]] - Code style section 10: the React (jsdotlua) stack, the Interface/ directory contract, component shape, hooks, plain-Lua state stores, one portalled root, ReactSpring-only animation, and scale-only layout with a shared theme module.
- [[Standards/code-style-script-headers-and-doc-comments|Code style §2: script headers and doc-comments]] - Code style section 2: the exact file header template (four to five prose lines at eighty columns saying what the file is), the function doc-comment with its blank line, and header hygiene.
- [[Standards/code-style-sixty-second-version|Code style §0: the sixty-second version and the ratified rules]] - Code style section 0: the eight fastest tells that identify code as Mike's, and the eight ratified rules that override every other section.
- [[Standards/code-style-strict-mode-and-types|Code style §3: strict mode and Luau type annotations]] - Code style section 3: where --!strict goes, the Config/Types pattern, aggressive annotation, and the rulings on bare requires, {} versus { [string]: any }, package any and class :: any.
- [[Standards/code-style-tooling-config-conventions|Code style §11: tooling config conventions]] - Code style section 11: Rojo project file and require roots, the WaitForChild-only-when-needed rule, Aftman pins, Wally manifest and gitignored Packages, selene, StyLua, one-line editor settings, .gitattributes, the branch and PR workflow, and vestigial files to delete.
- [[Standards/git-commits-are-manual|Git commits and pushes are done by the user]] - Claude never commits, pushes, merges or opens PRs; the user reviews and commits.
- [[Standards/kb-node-format|KB node format]] - Every node has YAML frontmatter, one H1, an Up link to its Path, and the sections from the Path template.
- [[Standards/kb-read-before-work|The KB is read before any work starts]] - Core, Decisions, Mistakes and Standards are in context before any work starts; hooks enforce it. Research is listed by index and opened on demand.
- [[Standards/one-node-per-thing|One node per thing]] - A node covers exactly one mistake, rule, topic, session or plan; never two, and never split.
- [[Standards/session-memory-node|One Memory node per session, short and current]] - Each session writes exactly one short Memory node and updates it, never duplicates it.
- [[Standards/working-with-mike|Working with Mike: what he knows and prefers]] - What Mike already knows and prefers, so sessions pitch explanations and decisions at the right level.
<!-- kb:auto-end -->
