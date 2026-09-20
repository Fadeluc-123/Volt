---
type: standard
date: 2026-09-20
session: 997a7da2
description: Claude never commits, pushes, merges or opens PRs; the user reviews and commits.
tags: [git, process]
---
# Git commits and pushes are done by the user
Up: [[Standards]]

**Rule:** Claude never runs `git commit`, `git push`, `git merge`, `git rebase`, `git cherry-pick` or `git revert`, and never creates or merges pull requests. Inspecting with `git status`, `git diff`, `git log` and staging with `git add` are fine.

**Why:** The user reviews every change before it enters history.

**How to apply:**
- Finish the change, leave it in the working tree, and end with a short list of what changed and is ready to commit.
- The PreToolUse hook (`.claude/hooks/kb-pretool.ps1`) denies the blocked commands. They are not worked around with other tools, scripts or wrappers.

**Exceptions:** none. If the user wants this changed, they edit the hook and this node.
