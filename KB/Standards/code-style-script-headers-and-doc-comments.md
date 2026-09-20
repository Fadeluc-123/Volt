---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 2: the exact file header template (four to five prose lines at eighty columns saying what the file is), the function doc-comment with its blank line, and header hygiene.
tags: [code-style, luau, comments]
---
# Code style §2: script headers and doc-comments
Up: [[Standards]]

**Rule:** Every file opens with a `--[[ ... --]]` prose header of four to five lines wrapped at eighty columns that says what the file is and nothing else, followed by a blank line, `--!strict`, and the first `game:GetService` with no blank line between. Every non-trivial public function gets a block doc-comment, a blank line, then the function.

**Why:** The header and the doc-comment gap are the strongest fingerprints of Mike's code (§0). The header cap exists because a narrower wrap turned a four-line budget into a nine-line average; eighty columns and five lines is checkable by eye.

**How to apply:**

### 2.1 The file header, exact template

```lua
--[[
    Every inventory in the game, registered as views: the bag, the hotbar, the
    clothing row, and everything a container owns. A view carries the set of
    players allowed to see it, and its adapter decides what may go in it.
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages
```

Non-negotiable details:
- Opens `--[[`, closes **`--]]`**, never bare `]]`.
- Body indented **4 spaces**, prose (not tags), hard-wrapped at **80 columns** at natural clause breaks.
- **Four to five lines, a hard cap** (amended 2026-08-26 from "2 to 4 lines at about 48 characters"). Sentence case, usually no terminating period.
- **It says what the file is, and nothing else.** Not why it was built, not what it replaced, not who decided it or when (§5.4). A constraint the code cannot show goes beside the line it constrains or in a doc-comment, not in the header.
- Blank line after `--]]`, then `--!strict`, then the first `game:GetService` with **no** blank line between them.
- Placeholder and stub files still ship an empty header: `--[[\n\n--]]`. Never no header.
- Acceptable but not preferred variant: `--!strict`, blank line, then the header.
- **LEGACY, do not write:** `--!strict` on line 1 above the docblock, closed with bare `]]`.

### 2.2 The function doc-comment

Block comment, **blank line**, then the function. This gap is the signature habit.

```lua
--[[
    Exposes an inventory type based on the
    given reference identifier, and can be
    used to read the inventory's data.
--]]

function Service:resolve(reference: Reference) : View?
	return self._registry[reference]
end
```

- Every non-trivial public function gets one: two to eight lines of *intent*, never a signature restatement, never the history of how it came to be (§5.4).
- Ad-hoc param docs when a param is non-obvious; no moonwave, no LuaDoc:
  ```lua
  --[[
      Publishes a character state to every subscriber.

      @ state | the new state event of the player (Ex: death)
  --]]
  ```
- Section banners for grouped helpers use the same block form: `--[[\n    Global functions\n--]]`.

### 2.3 Header hygiene

Header comments get copy-pasted and not updated. **When a file is duplicated, rewrite the header before anything else.**

**Exceptions:** none.
Related: [[Standards/code-style-overview]] [[Standards/code-style-comments-and-voice]] [[Standards/code-style-internal-script-layout]]
