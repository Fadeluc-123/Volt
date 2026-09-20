---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 4: the exact block order inside a script, function ordering, the public/private naming table with reserved verbs, and the blank-line rules.
tags: [code-style, luau, layout]
---
# Code style §4: internal script layout order
Up: [[Standards]]

**Rule:** Blocks appear in the fixed order below, separated by exactly one blank line, never two; functions are ordered constructor, public API in narrative order, private helpers, and always the lifecycle tail last.

**Why:** A fixed order lets a reader find every dependency, constant and type at a glance and makes every file scan the same.

**How to apply:**

### 4.1 The block order, exactly

```lua
--[[                                            (1) header block comment
    ...
--]]

--!strict                                       (2) strict mode
local Players = game:GetService("Players")      (3) services, roughly alphabetical
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages     (3b) Packages glued to the SAME block
local Player = Players.LocalPlayer              (3c) client only, always these two lines
local Client = Player.PlayerScripts.Client

local Knit = require(Packages.Knit)             (4) wally requires, Knit first
local Trove = require(Packages.Trove)

local Policy = require(ReplicatedStorage.Shared.Modules.Net.Policy)   (5) the inbound pipeline
local Guards = require(ReplicatedStorage.Shared.Modules.Net.Guards)
local Schemas = require(ReplicatedStorage.Shared.Modules.Net.Schemas.Inventory)

local Root = ServerScriptService.Server.Modules.Classes.Inventory   (6) first-party requires, bare (§3.3)
local Mutex = require(Root.Modules.Mutex)

local Assets: Folder = ReplicatedStorage:WaitForChild("Assets")   (7) typed instance handles; boot-time wait (§11.1)

local DEFAULT_SLOTS: number = require(ReplicatedStorage.Shared.Config.Containers.Inventory).space
local DRAG_THRESHOLD: number = require(Client.Modules.Config.Inputs).dragThreshold
                                                (8) SCREAMING_SNAKE constants, typed, read from Config

local Types = require(ReplicatedStorage.Shared.Config.Types.Inventory)   (9) types, bare (§3.2)
type Stack = Types.Stack
type Reference = Types.Reference

local Service = Knit.CreateService({ ... })     (10) the service table: Name, Client, Policy, _peers, _state

-- functions ...                                (11)

function Service:KnitStart() end                (12) lifecycle pair, always last
function Service:KnitInit()
	self.Client.sendSnapshot:SetTop({})
	self._characterService = Knit.GetService("CharacterService")
end

return Service                                  (13) blank line above, then return
```

- `local Packages = ReplicatedStorage.Packages` is appended to the service block with **no blank line**. Same for the client's `Player` / `Client` pair.
- `Packages` is **PascalCase** in feature files, lowercase `packages` **only** in the two `init.*.lua` bootstraps.
- Requires use absolute paths off `Client.` / `ReplicatedStorage.Shared.` / `ServerScriptService.Server.`, **not** `script.Parent`, except *inside a class family*, where relative is correct: `require(script.Modules.Stack)`, `require(script.Parent.SlotState)`.
- **Peer services are `_camelCase` fields declared `nil` in the service table (slot 10) and resolved with `Knit.GetService` in `KnitInit`** (2026-08-25). Never require a service module directly and never resolve a peer at module scope; `Knit.GetService` before `Knit.Start` errors.
- **LEGACY, do not write:** a bare forward-declared peer local in slot 9 (`local CharacterService`) assigned in `KnitInit`. The peer lives on `self` so every method reaches it the same way and the table literal shows every dependency.
- **Constants come from config.** `SCREAMING_SNAKE` typed locals stay, but they are read out of a `Config/` module rather than written as a literal.

### 4.2 Function ordering inside the module

1. Constructor / lifecycle setup (`Module.new`, `Service:_new`).
2. Public API in **narrative / call order**, the order a reader would follow the system.
3. Private `_helpers`, near their first caller, or grouped after the publics in `Modules/Classes` files.
4. `Service.Client:x` sits **immediately beneath** the `Service:x` it proxies.
5. Always, last, this exact tail:

```lua
function Service:KnitStart() end
function Service:KnitInit()
	self.Client.timeDisplay:SetTop(INTERMISSION)
end

return Service
```

Both lifecycle methods are **always written**, even when empty. The empty one collapses to a one-liner and goes **first**; the implemented one follows with no blank line between. If the work needs other services already started, flip it: `function Service:KnitInit() end` then a full `KnitStart`.

`KnitInit` does three things in this order: `:SetTop()` every `Client` property, resolve peers with `Knit.GetService`, set up player-observation bindings (§8.6). **`Policy.apply` is not one of them** (2026-08-25); it runs once in the bootstrap because Knit binds and captures every handler before the first `KnitInit` (§8.4). Every binding made in `KnitInit` is owned by the service's `Trove` and documented with the path that tears it down (§8.6).

### 4.3 Public vs private

| Kind | Convention | Example |
|---|---|---|
| Public method | camelCase | `Service:insert`, `Controller:toggle`, `Module:validate` |
| Private method | `_camelCase` | `Service:_publish`, `Component:_getTemplate` |
| Private state field | `_camelCase` | `self._profiles`, `self._trove` |
| Framework member | PascalCase, never renamed | `Client`, `Net`, `Policy`, `Init`, `Start`, `Construct`, `Stop`, `Instance` |
| Module-level mutable table | PascalCase | `TouchedPlayers`, `SkipTyping` |
| Function-scope local | camelCase | `newValue`, `playerInventory` |
| Constant | `SCREAMING_SNAKE` | `MAX_HUNGER`, `SNAP_THRESHOLD` |

**Reserved method verbs** (studio Notion guide, 2026-07-29). Use these exact words for these meanings and nothing else:

| Verb | Meaning |
|---|---|
| `new` | object creation; always a **function** (`.new()`), never a method |
| `create` | creating something within the context of an existing object |
| `add` | adding an existing item |
| `remove` | removing an item without destroying it |
| `delete` | destroying an item |
| `get` | retrieving one item |
| `getAll` | retrieving every item |

Method names never repeat what the module name already says: `PlayerStatService:update`, not `:updatePlayerStats`. Aim for one or two words.

Private state is declared **inline in the service table literal**, not in `Init`, each with a trailing comment, and a blank line separates each framework table from the private state fields (full shape in §8.2).

### 4.4 Blank-line spacing rules

- One blank line between every top-level function.
- One blank line between each require group / preamble block.
- One blank line between a doc comment and its `function`.
- One blank line between logical paragraphs inside a function (declarations / mutation / return).
- One blank line after a guard clause, before the main body.
- One blank line between entries in large table literals.
- One blank line before `return Service`.
- **None** immediately after a `function` opening line, and none before its `end`.
- **Never two consecutive blank lines anywhere.**

**Exceptions:** the two `init.*.lua` bootstraps (lowercase `packages`; see §8.4).
Related: [[Standards/code-style-overview]] [[Standards/code-style-knit-service-layout]] [[Standards/code-style-strict-mode-and-types]]
