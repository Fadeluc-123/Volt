---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 6: the stylua.toml config and how formatting is run, line width, quotes and interpolation, numbers and operators, control-flow shapes, the (boolean, string | nil) error convention, yielding returns a Promise, and the _G ban.
tags: [code-style, luau, formatting]
---
# Code style §6: formatting
Up: [[Standards]]

**Rule:** Tabs at width 4, 120 columns, Unix LF, double quotes, always-parenthesised calls, formatted through `lune run tools/format` (StyLua plus the anonymous-function space restore); guard clauses and `and`/`or` chains for control flow; service failures return `(boolean, string | nil)`; anything that yields returns a Promise; `_G` is banned.

**Why:** Formatting is mechanical so reviews are about substance. The error tuple keeps failures as values; the Promise rule keeps callers from inheriting unbounded stalls; the `_G` ban keeps every piece of shared state reachable through a require.

**How to apply:**

### 6.1 `stylua.toml`, the canonical config

```toml
column_width = 120
line_endings = "Unix"
indent_type = "Tabs"
indent_width = 4
quote_style = "AutoPreferDouble"
call_parentheses = "Always"
collapse_simple_statement = "Never"

[sort_requires]
enabled = false
```

Obey it. Formatting is run as `lune run tools/format`, not bare `stylua` (2026-08-25; see the anonymous-function line in 6.4 for why), and `stylua --check` is **not** wired up as a gate. The gate is `selene`, `rojo build` and `lune run tools/selfcheck`. New code: tabs, LF, StyLua enforced. When editing an existing 4-space file in an old repo, match that file rather than reformatting it.

### 6.2 Line width

Stay well under 120. Break a call one-argument-per-line once it exceeds about three arguments. Long interpolated strings break **inside the `{}`**:

```lua
	warn(`Successfully loaded {player.Name}'s profile with length: {
		#HttpService:JSONEncode(profile.Data)
	}`)
```

### 6.3 Quotes and strings

- **Double quotes** for plain literals and all Roblox API strings. **Never single quotes** in new code.
- **Backtick interpolation for every string carrying a value** (warns, errors, asserts, signal keys, datastore keys, model names) and frequently even when there is nothing to interpolate.
- `..` concatenation is absent. A message too long for one line becomes a local per clause and one interpolated string, never two backtick strings joined.
- **`string.format` is allowed** (2026-09-02) where the code wants a particular decimal place: `math.round` controls the value, not the printed width. Backtick interpolation is still the default.

```lua
	warn(`Item Registry does not exist for item: {item}`)
	error(`Invalid Stat Type {stat}`)
	return false, `Failed to find registered item data for {item}`
	local profileKey = `{player.UserId}`
	Tycoons:FindFirstChild(`Tycoon: {player.Name}`)
```

### 6.4 Numbers, operators, misc

- **Leading-dot fractions**: `.25`, `.05`, `.125`. StyLua may write these as `0.25` and that output is correct (2026-08-25).
- Compound assignment everywhere: `+=`, `-=`, `*=`, `..=`.
- `task.spawn` / `task.wait` / `task.delay` only. No `coroutine.*`, no bare `wait` / `spawn`, no `while true do` (use `while task.wait(1) do`).
- Trailing commas in multi-line **data** tables; **no** trailing comma on the last field of a service or controller table literal.
- Anonymous functions get a **space** after `function`: `return function (props: { [string]: any })`. Named functions do not: `function Service:get(...)`. StyLua strips this space and its only knob would also space every named definition, so `stylua` runs through `tools/format.lua`, which puts the space back. `function(` is never anything but an anonymous function, which is what makes the restore safe.

### 6.5 Control-flow shapes

Guard clauses and early return dominate. `return warn(...)` is the idiom for bail-with-message:

```lua
	if not itemRegistry then
		return warn(`Item Registry does not exist for item: {item}`)
	end
```

Multi-term conditions are exploded with **leading operators**, `if` and `then` alone on their own lines:

```lua
	if
		preferredSlot
		and preferredSlot >= 1
		and preferredSlot <= self.size
	then
```

**`and`/`or` chaining is the canonical conditional expression** (ratified 2026-07-29). Multi-term chains break with leading operators, one term per line, indented one level under the assignment:

```lua
local INTERMISSION: number = RunService:IsStudio() and 4 or 15 -- How long until first round starts

local text = loadFailed
	and "Failed to load! Retrying.."
	or not loadFailed
	and "No servers found for query!"
	or nil
```

**The one caveat.** `a and b or c` returns `c` whenever `b` is `false` or `nil`, so the chain misfires when the middle operand can legitimately be either (booleans, optional lookups, anything that may return `nil` on success). Handle those with an explicit `if`:

```lua
	-- Wrong: yields true whenever isMuted is false
	local muted: boolean = isMuted and false or true

	-- Right
	local muted: boolean
	if isMuted then
		muted = false
	else
		muted = true
	end
```

`if/then/else` expressions (`local x = if cond then a else b`) are **legacy**: leave them alone when editing an old file, write the `and`/`or` form in new code. A Studio-vs-live branch stays inline (a development affordance); anything a designer would tune is read from `Config/` (§1.3).

### 6.6 Error and result convention

- **Service-level failures return `(boolean, string | nil)` tuples**, never throw. Unpack with `select(2, ...)` at the call site.
- **`assert` guards invariants** in class constructors and mutators, with an interpolated message.

```lua
function Service:get(item: string) : (boolean, string | {})
	if self.registered[item] then
		return true, self.registered[item]
	else
		return false, `Failed to find registered item data for {item}`
	end
end

-- caller:
local itemData: { [string]: any } = select(2, ItemRegistryService:get(item))

	assert(type(size) == "number" and size > 0, "Inventory.new: size must be > 0")
```

### 6.6.1 Yielding returns a Promise (ratified 2026-07-29)

**Nothing blocks a caller to answer a question.**

- Anything that cannot answer immediately returns a **Promise**. The caller decides whether to `:andThen(...)` and carry on, or `:await()` because the next step genuinely cannot proceed without the answer.
- A predicate that *can* answer immediately stays synchronous and returns a success tuple. Do not wrap a pure check in a Promise for symmetry.
- **Validators never yield and never await.** A guard that needs a character waits for nothing; it reads current state and rejects if the state is not there.
- Every Promise has a timeout or a rejection path. `repeat task.wait() until cond` is not an async primitive (§13).

```lua
	local alive: boolean, reason: string? = IsAlive(player)      -- answerable now

	IsAlive(player):andThen(function(alive: boolean)             -- needs the character; caller decides
		...
	end)

	local alive: boolean = IsAlive(player):await()               -- only where the next step is impossible without it
```

### 6.7 `_G` is banned

**No `_G` in any script in the workspace** (ratified 2026-07-29). Not for caching, not for cross-script handoff, not for debugging. Shared state goes through a required module; cross-realm state goes through the network layer (§9); per-instance state lives on `self`. Vendored packages under `Modules/Libraries/` and Wally `Packages/` are the only exemption, and they are never restyled anyway. Accidental globals (a module-level `function name()` with no `local`) fall under the same ban (§13).

**Exceptions:** vendored packages for the `_G` ban; existing 4-space files in old repos for indentation.
Related: [[Standards/code-style-overview]] [[Standards/code-style-sixty-second-version]] [[Standards/code-style-tooling-config-conventions]] [[Decisions/no-global-state-unique-remote-scope]]
