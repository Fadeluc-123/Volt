---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 5: comment density and shape, no magic arguments, the Whiteoak TODO and FIXME markers, Mike's voice, and the rule that a comment never records a decision.
tags: [code-style, luau, comments]
---
# Code style §5: comment structure, density and voice
Up: [[Standards]]

**Rule:** At most one comment per four to eight lines, explaining *why* and never restating *what*; bare literal arguments become named variables; deferred work is `-- Whiteoak TODO:` and broken things `-- Whiteoak FIXME:`; and no comment anywhere records a decision, attribution, date or history.

**Why:** A comment that restates the line under it is noise. A literal in an argument list says nothing at the call site or in a stack trace. Decisions written into source rot the day the vault moves and cannot be found from the vault; the KB is the record, the code carries only the constraint.

**How to apply:**

### 5.1 Inline narration

Single-line `--` above each logical block, sentence case, **no terminating period**, informal, sometimes exclamatory. Section comments start with a verb (`-- Ensure ...`, `-- Load ...`, `-- Cancel any playing tweens`).

```lua
	-- Ensure player's inventory isn't full
	meshPart:SetNetworkOwner(nil) -- So worker doesn't lag and freeze mid movement
	connection() -- Disconnects our connection
```

Multi-branch algorithms get numbered steps (`-- 1) Try preferred slot`, `-- 2) Merge into existing stacks`, `-- 3) Fill empties`). Data-loss footguns get multi-line justifications:

```lua
	-- Set the datastore since this is the first time, if we don't, template takes over
	-- and script assumes it's not first time, which is incorrect
```

**Magic arguments do not exist; they become named variables** (ratified 2026-07-29). Name it, type it, and let the name carry the meaning; add a comment only if the name cannot:

```lua
	-- Legacy: the value is explained, but the call site still reads as noise
	self:teleportPlayer(player, survivorSpawn, 4 --[[So player is teleported into the ground]])

	-- Canonical
	local spawnDepth: number = SpawnConfig.depth -- Sinks the player into the ground on arrival
	self:teleportPlayer(player, survivorSpawn, spawnDepth)
```

The variable does not have to escape the function; a function-scope local is the normal case. If the value is tunable rather than incidental, it belongs in a `Config/` module (§1.3) and the local reads it from there.

### 5.2 TODO markers, canonical form

- **`-- Whiteoak TODO:`** for deferred work. Placed directly under the header (grouped) or directly above the relevant line.
- **`-- Whiteoak FIXME:`** for something *broken* that needs fixing, same placement.
- Both markers are always assumed accurate and outstanding, and searchable with Ctrl+F.
- **LEGACY, do not write:** a numbered `-- TO:DO` block under the header.

```lua
-- Whiteoak TODO: Implement distance checks, user context screen (is inventory opened?), and more!
-- Whiteoak FIXME: Does not close
```

### 5.3 Voice

Casual, first-person-plural, occasionally jokey or self-deprecating. Keep it; sanding it off reads as *not him*.

```lua
	assert(actor, `What the hell, how'd you forget adding the player to the actor :/`)
	_owner = nil, -- 2 different tables are never the same, perfect in this indentifier case
	-- Comeback to this later, it's a bit of a mess
```

When a pattern is borrowed from literature, cite the URL in the header comment (`https://refactoring.guru/design-patterns/builder`). Typos in existing comments are left alone: do not introduce them, do not rewrite them.

### 5.4 A comment never records a decision

Ruled 2026-08-26, binding on every comment: header, doc-comment and inline alike. None of this goes in a `.lua` file:

- **Attributions.** No `(Mike, 2026-08-26)`, no name, no initials.
- **Dates.** No `2026-08-25`, no "as of", no "until".
- **Rulings.** No "settled", "ruled", "red-penned", "Mike asked for".
- **History.** Not what the code used to do, not what the first version got wrong, not what was tried and thrown away, not what the reference place did differently.
- **Measurements taken once.** "Measured in the place on 2026-08-26" is a session's working, not a fact about the code.
- **Markdown and shouting.** No `**bold**`, no `SHOUTY CAPS` for emphasis. A `.lua` file is not a note.

All of it belongs in the KB and only there. **What stays is the constraint, not its provenance.** If a rule matters, state the rule beside the line it governs and stop:

```lua
	-- Legacy: the constraint is buried in a decision log
	-- Only the ROOT is anchored (Mike, 2026-08-26) -- anchoring every part froze
	-- the joints and the body stood upright, which read as a bug

	-- Canonical
	-- Only the root is anchored: an anchored part does not move for an
	-- animation, so anchoring the rest freezes the pose
```

Nothing here overrides 5.1's data-loss footguns. A Roblox behaviour the code cannot show (`Clone()` returning nil on an unarchivable instance, a sparse table collapsing in a DataStore, a Humanoid restoring its own collision) is exactly what a comment is for, and it survives this rule with its date and attribution stripped.

**Exceptions:** none.
Related: [[Standards/code-style-overview]] [[Standards/code-style-script-headers-and-doc-comments]] [[Standards/code-style-sixty-second-version]]
