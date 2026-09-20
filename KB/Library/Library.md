---
type: path
description: Long-form source documents kept verbatim for citations and detail, such as research reports and researcher notes. Listed at session start; opened on demand.
---
# Library
Up: [[Core]]

One node per document. The Library holds long-form material that would lose value if condensed: research reports with a URL per claim, researcher notes with cited findings and gaps, and similar documents handed to the project. They are kept verbatim behind a short frontmatter and a snapshot notice.

The Library is evidence, not the current answer. The distilled, maintained knowledge lives in Research, Decisions and Planning nodes, and each of those links to the Library node it draws from. If a Library document and a Research or Decisions node disagree, the Research or Decisions node wins and the Library document is a snapshot of what was known when it was written.

**Read at session start:** listed only (this index). Open a document with Read when a Research node points here for detail or when a citation is needed.

## When to add a node

When a document arrives that is too long or too citation-dense to split into Research nodes without losing the citations. Write the Research nodes first; then file the source here and link both ways. Do not add code, transcripts or binary files; source snapshots go in the repository's `Reference/` folder and are described by a Research node.

## Node template

File name: a short kebab-case slug that names the document, for example `zap-vs-blink-report.md`. Keep the document body verbatim below the notice; do not edit it to keep it current. If it is superseded, say so in the notice and link the replacement.

```md
---
type: library
date: YYYY-MM-DD
session: <first 8 chars of session id>
origin: <where the document came from: author, session, tool>
description: <one line: what the document is>
tags: []
---
# <Document title>
Up: [[Library]]

> Snapshot from <date>. Kept verbatim for citations and detail. Current knowledge: [[Research/...]], [[Decisions/...]].

<document body>
```

## Nodes
<!-- kb:auto-start -->
- [[Library/benchmark-and-changes-since-notes|Blink benchmark and changes since (researcher notes)]] - Researcher notes behind the report: nine questions on the published benchmark, its method, numbers, reproducibility and every relevant release since.
- [[Library/blink-current-state-notes|Blink current state (researcher notes)]] - Researcher notes behind the report: eight questions on Blink 0.18 and 1.0 with the full release timeline, IDL coverage, cited findings and gaps.
- [[Library/community-and-ecosystem-notes|Community and ecosystem (researcher notes)]] - Researcher notes behind the report: eight questions on sentiment, docs perception, tooling, adoption, bus factor, interop and runtime safety.
- [[Library/handoff-2026-09-20|Handoff 2026-09-20: our own Roblox buffer-networking package]] - The forward-looking handoff written before the Volt folder existed: deliverables, goals, from-scratch versus fork, strengths, bugs, coverage list, architecture notes, benchmark plan, names.
- [[Library/session-context-2026-09-20|Session context 2026-09-20: Zap vs Blink research and the decision to build Volt]] - The consolidated knowledge of the 2026-09-20 research session, tagged by kind: decisions, facts, explanations, preferences, requirements, open questions.
- [[Library/zap-current-state-notes|Zap current state (researcher notes)]] - Researcher notes behind the report: nine questions on Zap with takeaways, cited findings, inferences and gaps.
- [[Library/zap-vs-blink-report|Zap vs Blink for Roblox networking (research report)]] - The full 2026-09-20 research report recommending Zap 0.6.29 for a new project, with a URL for every claim.
<!-- kb:auto-end -->
