---
type: path
description: Things that went wrong and the rule that prevents a repeat. Read in full at every session start.
---
# Mistakes
Up: [[Core]]

One node per mistake. A mistake is anything that cost time or produced a wrong result: a bad assumption, a misread requirement, a broken build, a misused tool, a broken rule. The node exists so it never happens twice.

**Read at session start:** always, in full (injected by the SessionStart hook).

## When to add a node

As soon as the mistake is recognised and corrected, and at the latest before the turn ends. If a mistake already listed here happens again, add a new node that links to the old one and says why the old rule was not enough.

## Node template

File name: a short kebab-case slug that names the mistake, for example `assumed-pwsh-was-installed.md`.

```md
---
type: mistake
date: YYYY-MM-DD
session: <first 8 chars of session id>
description: <one line: what went wrong>
tags: []
---
# <What went wrong, one line>
Up: [[Mistakes]]

**Context:** what was being done.
**Mistake:** what happened and why it was wrong.
**Cost:** what it broke or wasted.
**Fix:** what corrected it.
**Rule:** the one-line rule that prevents it next time.
Related: [[Standards/...]] [[Memory/...]]
```

## Nodes
<!-- kb:auto-start -->
- [[Mistakes/shell-heredoc-tripped-git-guard|Shell heredoc containing "git commit" was denied by the git guard]] - A shell heredoc whose file content mentioned the blocked git commands was denied by the git guard, silently dropping every other write in the same command.
<!-- kb:auto-end -->
