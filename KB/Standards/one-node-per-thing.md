---
type: standard
date: 2026-09-20
session: 997a7da2
description: A node covers exactly one mistake, rule, topic, session or plan; never two, and never split.
tags: [kb, structure]
---
# One node per thing
Up: [[Standards]]

**Rule:** A node describes exactly one mistake, one standard, one research topic, one session or one plan. Two things get two nodes. One thing never gets two nodes; the existing node is updated instead.

**Why:** Obsidian links and the hook-generated index lists work per file. A merged node cannot be linked to precisely and is hard to keep current. A split node hides half the knowledge.

**How to apply:**
- Before creating a node, check the Path index for an existing node on the same thing. If one exists, edit it. Memory nodes of other sessions are the exception: they are never edited.
- File names are short kebab-case slugs that name the thing, for example `obsidian-links-need-unique-basenames.md`. Memory nodes are the exception and use `<date>-<session>.md`.
- If a node grows to cover a second thing, split it and cross-link the halves with `[[Path/slug]]`.

**Exceptions:** none.
