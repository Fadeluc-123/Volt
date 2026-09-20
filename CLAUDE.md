# Volt - Claude Code instructions

## Address the user as Mike

Every message to the user opens by addressing him as Mike. A message that does not is an early sign of context rot; the rule is `KB/Standards/address-mike-in-every-message.md`.

## The knowledge base (KB) is mandatory

`KB/` is this project's persistent memory. It is an Obsidian vault and it grows every session.
Structure: **Core -> Path -> Node**.

- `KB/Core.md` is the entry point. It links to every Path.
- A **Path** is a folder inside `KB/` with an index note of the same name, for example `KB/Mistakes/Mistakes.md`. The index says what belongs there, gives the node template, and lists the nodes.
- A **Node** is one `.md` file about exactly one thing. Never combine two things into one node.

Paths: Decisions, Library, Memory, Mistakes, Planning, Research, Standards.

**Before any work in a session**, `KB/Core.md` and every node in `KB/Decisions`, `KB/Mistakes` and `KB/Standards` must be in context. `KB/Library`, `KB/Memory`, `KB/Planning` and `KB/Research` are listed by index and opened with Read when relevant; check the Research index before researching anything.
The SessionStart hook injects all of this automatically (look for the "VOLT KNOWLEDGE BASE" block). If that block is missing, read those files with the Read tool. Write, Edit, shell, Agent and web tools are denied by the PreToolUse hook until the KB is read.

**Before ending any turn that did work**, create or update this session's Memory node at the path printed in the injected context (`KB/Memory/<date>-<session>.md`), and add nodes to Mistakes, Research, Standards or Decisions for anything new. The Stop hook refuses to end the turn until the Memory node is written.

## Hard rules

1. Never run `git commit`, `git push`, `git merge`, `git rebase`, `git cherry-pick`, `git revert`, or create or merge pull requests. The user reviews and commits. A hook blocks these. The guard also matches those words inside a shell command's text, so files that mention them are written with the Write or Edit tool.
2. One node per thing. Update an existing node rather than creating a second one about the same thing. Never edit or delete another session's Memory node.
3. Memory nodes are short: what, why, how, outcome, open threads. Not a session log. Aim for under 25 lines.
4. Record a mistake in `KB/Mistakes` as soon as it is recognised and corrected. Never repeat one that is already recorded.
5. Record research in `KB/Research` when it produces reusable knowledge, one node per topic. Long source documents go verbatim in `KB/Library`.
6. Record every ruling Mike makes about Volt in `KB/Decisions`. Do not re-litigate a recorded decision; if it needs reopening, say so and ask.
7. All Luau written for Volt follows the `code-style-*` nodes in `KB/Standards`. They are law, not guidance.
8. Do not hand-edit the lists between `<!-- kb:auto-start -->` and `<!-- kb:auto-end -->`. Hooks regenerate them.

## Repository layout

- `KB/` the knowledge base (Obsidian vault).
- `Reference/` gitignored, local-only snapshots of third-party source (Blink 0.18, Blink 1.0 rewrite, Zap 0.6.x) kept for design reference. Never restyled, never edited. If the folder is missing, re-fetch it as described in `KB/Research/reference-source-snapshots.md`.
- `Handoffs/` gitignored inbox for bundles from other sessions awaiting ingestion into `KB/`.
- `.claude/` hooks and settings that enforce the KB workflow.

## Enforcement

Hooks live in `.claude/settings.json` and call the PowerShell scripts in `.claude/hooks/`. Per-session markers are written to `.claude/state/` (gitignored). Do not disable or bypass them. The rules themselves are documented as nodes in `KB/Standards/`.
