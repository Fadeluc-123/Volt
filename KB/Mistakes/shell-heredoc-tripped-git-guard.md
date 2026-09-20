---
type: mistake
date: 2026-09-20
session: 14e4b904
description: A shell heredoc whose file content mentioned the blocked git commands was denied by the git guard, silently dropping every other write in the same command.
tags: [hooks, git, tooling]
---
# Shell heredoc containing "git commit" was denied by the git guard
Up: [[Mistakes]]

**Context:** Rewriting `CLAUDE.md` and three auto-memory files in one Bash command using heredocs.
**Mistake:** The new `CLAUDE.md` text lists the forbidden commands ("Never run `git commit`, `git push`..."). The PreToolUse git guard matches those words anywhere in the command text, including heredoc bodies, so the whole command was denied. Because four writes were chained in one command, none of them happened, and the failure was only visible in the tool error.
**Cost:** One wasted tool call and a re-issue of four writes.
**Fix:** Wrote `CLAUDE.md` with the Write tool (after a Read) and re-ran the memory writes in a separate shell command that does not mention the blocked commands.
**Rule:** Any file whose content names a blocked git command is written with the Write or Edit tool, never through a shell heredoc; and unrelated writes are not chained behind a command that might be denied.
Related: [[Standards/git-commits-are-manual]] [[Memory/2026-09-20-14e4b904]]
