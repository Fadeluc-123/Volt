---
type: standard
date: 2026-09-20
session: 997a7da2
description: Every node has YAML frontmatter, one H1, an Up link to its Path, and the sections from the Path template.
tags: [kb, format]
---
# KB node format
Up: [[Standards]]

**Rule:** Every node is a Markdown file with YAML frontmatter (`type`, `date`, `session`, `description`, `tags`, plus any fields the Path template adds), exactly one H1 title, an `Up: [[<Path>]]` link on the line after the title, and then the sections from the Path's template.

**Why:** The hooks read `description` (falling back to the H1) to build the index lists, and the `Up:` links give Obsidian the Core -> Path -> Node graph.

**How to apply:**
- Copy the template from the Path index note, `KB/<Path>/<Path>.md`.
- `description` is one specific line. It is what appears in the index.
- Link related nodes as `[[Path/slug]]`. The vault root is `KB/`, so `[[Mistakes/some-slug]]` resolves from anywhere. `[[Core]]` and `[[<Path>]]` resolve because those basenames are unique.
- Never hand-edit text between `<!-- kb:auto-start -->` and `<!-- kb:auto-end -->`. The hooks regenerate it from the folder contents.
- Files are UTF-8 without BOM. Prefer plain ASCII punctuation.

**Exceptions:** `KB/Core.md` and the Path index notes have their own frontmatter (`type: core`, `type: path`) and no `Up:` link requirement beyond `[[Core]]` in the index notes.
