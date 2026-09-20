---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 3: where --!strict goes, the Config/Types pattern, aggressive annotation, and the rulings on bare requires, {} versus { [string]: any }, package any and class :: any.
tags: [code-style, luau, types]
---
# Code style §3: strict mode and Luau type annotations
Up: [[Standards]]

**Rule:** `--!strict` on nearly every file, shared types in `src/Shared/Config/Types/<Domain>.lua`, aggressive annotation of locals and loop variables, and a require carries an annotation only when the annotation is true.

**Why:** Strictness is aspirational and accepted as imperfect, but wrong annotations are worse than none: `local Types: {} = require(...)` put `Undefined type` under every alias in 80 files and `local Config: {} = require(...)` produced `Key not found` in 231 files (2026-08-31 to 2026-09-01).

**How to apply:**

### 3.1 Where `--!strict` goes and which files get it

- Position: **after** the header block, immediately above the first `game:GetService` line.
- Coverage: near-universal. Every service, controller, component, class and `Modules/**` file. Legitimately omitted: Cmdr entry scripts, vendored libraries, trivially pure config and data tables.
- Strictness is aspirational: the code does not always typecheck cleanly and that is accepted. Do not sacrifice the idioms to satisfy the analyzer, but do not introduce *new* obviously-wrong types either.

### 3.2 Where types live: the `Config/Types` pattern

Shared types live in `src/Shared/Config/Types/<Domain>.lua`. Each file `export type`s its shapes and returns an empty table:

```lua
--[[
    Types used by the inventory system, shared
    between the server class and the interface.
--]]

--!strict
export type Stack = {
	item: string,
	quantity: number,
	properties: {}?
}

export type Reference = string

return {}
```

Consumers require once, then alias at the top of the file, one alias per line, blank line after the require:

```lua
local Types = require(ReplicatedStorage.Shared.Config.Types.Inventory)

type Stack = Types.Stack
type Reference = Types.Reference
```

- **A require carries no annotation unless the annotation is TRUE** (2026-08-31, widened 2026-09-01). An explicit annotation *replaces* the binding's module type and everything the module exports goes with it. Bare is what makes `type Stack = Types.Stack` resolve and `Config.tag` a string. The rule reaches any module aliased from in type position (types files, config files, interface state stores) and the decorative annotation of 3.3, which is written only where accurate and deleted rather than corrected where it is not.
- Module-local types that nothing else consumes are declared inline as `type X = { ... }` in the same slot (after requires, before constants), fields camelCase.

### 3.3 Annotation style

**Annotate aggressively: locals, loop variables, constants, instance handles, even where inference is obvious.**

```lua
local DEFAULT_SLOTS: number = require(ReplicatedStorage.Shared.Config.Containers.Inventory).space
local BACKUP_TIMEOUT: number = .25
local Assets: Folder = ReplicatedStorage:WaitForChild("Assets") -- Boot-time wait: Assets may not have replicated yet

local distance: number = (a - b).Magnitude
local token: {nil} = {}

for _, player: Player in players do
for stat: string, value: number in savedStats do
```

- **Return types get a space before the colon**: `function Service:get(player: Player) : { [string]: any }`. Parameter colons stay tight. Void is `: ()`. StyLua may close that space to `): ...` and its output is correct (2026-08-25); the space is no longer preserved by hand.
- `string | nil` in return positions, `string?` in parameter positions.
- **`{}` is not "some table"; it is a table with no properties** (2026-09-01), and Luau reads it that way everywhere: every key read off one is an error (1,777 of them were). Write `{ [string]: any }` where the shape is genuinely open.
- Tuple returns are annotated: `: (boolean, string | nil)`.
- **The decorative require annotation** is written where it is the module's real signature and nowhere else:
  ```lua
  local Hinge: (CFrame, Model, number) -> CFrame = require(ReplicatedStorage.Shared.Components.Hinge)
  local Mutex = require(Root.Modules.Mutex)                              -- the module's own type is already right
  local Types = require(ReplicatedStorage.Shared.Config.Types.Inventory) -- a types require never carries one
  ```
  The old `{}` and `{(any?) -> any?}` forms are gone. `typeof(require(...))` is the sanctioned upgrade where the type wants a name; bare is the same thing with less to read.
- **A package takes `: any` where its published types do not describe how this code calls it** (2026-09-01): Knit resolves to `KnitServer` on both realms so the client's `GetController` is unknown; a Component has methods assigned onto the table the package returns; Echo is given an action key; ReactSpring is handed a config block. `Packages/` is Wally's to rewrite, so the truth is told at the require. Nothing else takes `any` for want of thinking.
- **A metatable class table takes `:: any` where `self` has no type** (2026-09-01). Luau gives `self` nothing in `function Class:method()` under the shape §7.1 ratifies, so arithmetic on a field is "Unknown type used in + operation".
- **`Root` local** when three or more siblings are required out of one class folder, bare like a require, because `: ModuleScript` replaces the type the sourcemap gives it and hides every child:
  ```lua
  local Root = ServerScriptService.Server.Modules.Classes.Inventory
  ```
- Generalized iteration only. **No `pairs`, no `ipairs`**; their presence is the tell for vendored code.

**Do not write:** `: table` (not a Luau type), `{string: number}` map syntax (must be `{[string]: number}`), pointless casts like `Name = "InputController" :: string`.

**Exceptions:** vendored code; files legitimately without `--!strict` as listed in 3.1.
Related: [[Standards/code-style-overview]] [[Standards/code-style-internal-script-layout]] [[Standards/code-style-module-and-class-patterns]]
