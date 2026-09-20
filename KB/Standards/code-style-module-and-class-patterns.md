---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 7: the only four module shapes (metatable class, singleton table, single-function module, builder DSL), the Actions/Functions/Adapters decomposition, and the pub/sub idiom with the empty-table token.
tags: [code-style, luau, architecture]
---
# Code style §7: module and class patterns
Up: [[Standards]]

**Rule:** Four module shapes and only four; composition over inheritance; a non-trivial domain class is a folder decomposed into `Actions/`, `Functions/`, `Adapters/`, `Anticheat/` and `Modules/`; a predicate written twice becomes a shared extension.

**Why:** A fixed set of shapes makes every module recognisable. The folder decomposition keeps the Knit service a thin façade and gives every verb one file. One implementation per predicate is what stops copies drifting.

**How to apply:**

### 7.1 Metatable class (canonical)

Declared **immediately after `--!strict`, before the services block**:

```lua
--!strict
local Mutex = {}
Mutex.__index = Mutex

local ReplicatedStorage = game:GetService("ReplicatedStorage")
...

function Mutex.new(timeout: number?)
	return setmetatable({
		_owner = nil, -- 2 different tables are never the same, perfect in this indentifier case
		_timeout = timeout or BACKUP_TIMEOUT
	}, Mutex)
end
```

- Named **`Module`** when the file's own name carries the meaning (`Grid.lua`, `Preview.lua`, `Validate.lua`); named **concretely** when the type travels between files (`Inventory`, `Stack`, `Mutex`, `Furnace`).
- Constructor is `.new()`, teardown is `:destroy()` (lowercase). State table declared **inline** in the `setmetatable` call.
- **Composition over inheritance, even for metatables** (ruled 2026-07-29). Prefer composing behaviour (Actions/Functions/Adapters folders, wrapped members, shared predicates) over extending a base class. New code reaches for inheritance only when composition genuinely cannot express the relationship.
- Inheritance, legacy reference only: `local Module = setmetatable({}, Base)` plus `Module.__index = Module`, constructor `setmetatable(Base.new(...), Module)`.
- **Superseded variant, do not write:** `setmetatable(self, { __index = table.clone(Module) })`, a per-instance copy of the method table.

### 7.2 Singleton table module

`local Module = {}` with no `__index`, methods via `Module:fn()`. For stateless coordinators and shared validators.

### 7.3 Single-function module

Every file under `Actions/`, `Functions/`, `Adapters/`, `Extensions/`, `Checks/` returns **one anonymous function**, named by the require site. Note the space in `function (`:

```lua
--[[
    Moves a stack from one inventory reference
    into another, locking both for the duration.
--]]

--!strict
...

return function (reference: Reference, slot: number, quantity: number) : (boolean, string | nil)
	...
end
```

**A predicate written twice becomes an extension** (ratified 2026-07-29). The dot-product facing check is the worked example: re-typed per system in the old codebases, every copy drifted and had to be re-audited. It is now one file, `src/Shared/Extensions/IsFacing.lua`, required by everything that asks the question. Same for distance, alive and line-of-sight checks. If the predicate carries state or needs configuration, it graduates to a class under `Shared/Classes/`; either way there is exactly one implementation and both realms require the same one.

### 7.4 Builder / fluent DSL

For static definition registries. Every method mutates `self` and `return self`; chained with leading-colon lines:

```lua
ItemDefinition.new("Foundation_Square_Wood", 1, "rbxassetid://14814443939", "", Buildings.Final.Wood)
	:building({
		maxDistance = 20,
		supportsFreePlacement = true,
		rotationStep = 90,
		allowedSockets = {"FoundationSocket"}
	})
```

### 7.5 The Actions / Functions / Adapters decomposition, the flagship pattern

**The most important architectural pattern, reproduced for any non-trivial system.** A domain class is a folder, not a file:

| Sub-folder | Contains | Shape |
|---|---|---|
| `init.lua` | The class: constructor, state, low-level accessors and mutators (`get`, `getSlot`, `setSlot`, `findFirstEmpty`, `insert`, `remove`) | metatable class |
| `Actions/` | One user-facing operation per file: `Insert`, `Delete`, `Split`, `Swap`, `Transfer`, `Drop` | returned function; locks, validates, mutates, publishes |
| `Functions/` | Pure or small helpers shared by the Actions: `CanTransfer`, `ChangedSlots`, `LockPair`, `UnlockPair`, `StackToNet` | returned function |
| `Adapters/` | Per-container permission policy implementing `canInsert` / `canExtract` / `canSwap` | table of predicates |
| `Anticheat/` | `init.lua` dispatcher plus `Checks/<Name>.lua` | returned functions |
| `Modules/` | Private classes only this domain uses: `Actor`, `Mutex`, `Signal`, `Stack` | metatable classes |

The Knit service that owns the domain becomes a **registry plus network façade** and nothing more.

### 7.6 The pub/sub idiom

A `_listeners` bucket keyed by identifier or by an empty-table token, a private `_publish`, and a `subscribe` that returns its own disconnect closure:

```lua
	local token: {nil} = {}
	bucket[token] = callback

	-- Cleanup
	return function()
		bucket[token] = nil
	end
```

The **empty table as a unique identity token** is a house primitive, used here and as the mutex owner.

**Exceptions:** none.
Related: [[Standards/code-style-overview]] [[Standards/code-style-file-and-folder-naming]] [[Standards/code-style-knit-service-layout]]
