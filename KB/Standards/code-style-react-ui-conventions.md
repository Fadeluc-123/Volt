---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 10: the React (jsdotlua) stack, the Interface/ directory contract, component shape, hooks, plain-Lua state stores, one portalled root, ReactSpring-only animation, and scale-only layout with a shared theme module.
tags: [code-style, luau, react, ui]
---
# Code style §10: React (jsdotlua) UI conventions
Up: [[Standards]]

**Rule:** Function components only, `createElement` aliased last before the first component, one portalled React root for the whole client, ReactSpring as the only animation system, plain-Lua state stores bridged by hooks, and visual values from one theme module.

**Why:** The `Interface/` contract lets a screen be added with zero registration code; one root and one animation system keep UI behaviour uniform; the theme module enables whole-theme swaps and light/dark support.

**How to apply:**

### 10.1 Stack

React (jsdotlua, `^17.2`) plus ReactRoblox plus ReactSpring 2.0.0 (chriscerie). **Function components only, always.** ReactSpring is the sole animation system; `TweenService` never appears in `Interface/`.

### 10.2 Directory contract (canonical)

```
Interface/
├── App.lua                 -- walks Core/Screens, mounts every ModuleScript, key = string.lower(screen.Name)
├── AppProviders.lua        -- auto-collects every Contexts/*.provider
├── ComposeProviders.lua    -- folds the provider list right-to-left
├── Config/Screens/...      -- per-screen data, e.g. { space = 30 }
├── Contexts/<Name>.lua     -- returns { provider = function(props) ... end, context = <Context> }
├── Core/Screens/<Screen>/  -- init.lua + Children/<Sub>/init.lua + Elements/<Leaf>.lua
├── Hooks/<Domain>/         -- bridges plain-Lua State stores into React
├── Shared/UIBridge.lua
├── State/<Domain>/         -- plain-Lua stores, zero React imports
└── Templates/<Thing>.lua   -- React.memo'd leaf components
```

**Adding a screen requires no registration code.** Drop a ModuleScript under `Core/Screens` and `App.lua` mounts it. `App.lua`'s header documents the whole pattern in Q&A form; keep that habit.

### 10.3 Component shape

```lua
--[[
    The inventory screen: a 24 slot grid the
    player opens with Tab.
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Player = Players.LocalPlayer
local Client = Player.PlayerScripts.Client

local React = require(Packages.React)
local ReactSpring = require(Packages.ReactSpring)

local useInventory = require(Client.Interface.Hooks.Inventory)

local createElement = React.createElement

return function(props: {visible: boolean, injected: { [string]: any }?})
	local slots, setSlots = React.useState({})
	...

	return createElement("ScreenGui", { ... }, {
		InventoryFrame = createElement("Frame", { ... }, {
			UIGridLayout = createElement("UIGridLayout", { ... }),
			Slots = ...
		})
	})
end
```

- `local createElement = React.createElement` is aliased at the top of **every** UI file and is the **last** alias line before the first component.
- Every screen is `return function(props: {...})`; never a class, never `React.forwardRef` unless an imperative handle is genuinely required.
- Props are typed inline; `props: { [string]: any }` is the pass-through shape, **not `props: {}`** (2026-09-01; see §3.3).
- Props are read by access (`props.item`), not destructured into locals.
- **Element-tree keys**: PascalCase for structural frames and Roblox instance types (`InventoryFrame`, `UIGridLayout`, `Slots`); lowercase for leaf decorations (`icon`, `quantity`, `durability`).
- Dynamic lists are built into a local table with interpolated keys, then merged with static children: `slotElements[`Slot_{index}`] = createElement(InventorySlot, { ... })` then `Sift.Dictionary.merge({ UIGridLayout = ... }, slotElements)`.
- Conditional children use `and`-chaining (§6.5): `durability = props.item and createElement("Frame", { ... })`, `StatsDisplay = isAlive and createElement(StatsDisplay) or nil`. The `if/then/else nil` form is legacy.
- Event handlers go **last** in the props table, each preceded by a blank line:
  ```lua
  	Size = UDim2.fromScale(.2, .1),

  	[React.Event.MouseEnter] = function()
  		SoundController:playInterfaceSound("Hover")
  	end,
  ```
- Leaf templates are wrapped in `React.memo`.

### 10.4 Hooks

- `local x, setX = React.useState(init)`.
- `React.useEffect(function() ... return function() connection:Disconnect() end end, {})`: cleanup is an inline closure, unless the source already returns a disconnector, in which case return it directly.
- Dep arrays are literal Lua tables: `{}`, `{serverDatas, props.searchQuery}`.
- Forward-declared connections inside effects use the semicolon tic:
  ```lua
  	local connection;
  	connection = InventoryService.sendPatch:Observe(function(patch: { [string]: any })
  		applyPatch(patch)
  	end)
  ```
- **Never call a hook conditionally.** Conditional `useEffect`s in older repos are bugs, not conventions.

### 10.5 State stores, hooks and contexts

Non-React state lives in `Interface/State/<Domain>/*.lua` as **plain Lua modules** (no React import) exposing `get` / `set` / `subscribe`, where `subscribe` returns its own disconnect closure. `Interface/Hooks/<Domain>/*.lua` bridges a store into React with `useState` plus `useEffect`. Contexts export both halves so `AppProviders` can auto-collect them:

```lua
local ScreenContext = React.createContext({})

return {
	provider = function(props: {children: { [string]: any }})
		...
		return createElement(ScreenContext.Provider, { value = value }, props.children)
	end,

	context = ScreenContext
}
```

### 10.6 Mounting

**One root for the whole client**, created by a dedicated controller (`UIRootController`) at `KnitStart`, `ResetOnSpawn = false`:

```lua
	local root = ReactRoblox.createRoot(Instance.new("Folder"))
	root:render(ReactRoblox.createPortal(createElement(App), playerGui, "InterfaceUI"))
```

Superseded variant, do not write: one `ScreenGui` and root per controller inside `observeCharacter`. Screens that must escape ZIndex inheritance (drag layers, tooltips) get their own top-most `ScreenGui` with `DisplayOrder = 999`.

### 10.7 Animation

ReactSpring only.

```lua
	local styles, api = ReactSpring.useSpring(function()
		return { transparency = 1, config = { duration = .2 } }
	end)

	-- declarative when derived from props:
	local styles = ReactSpring.useSpring({
		from = { transparency = 1 },
		to = { transparency = props.visible and 0 or 1 },
		config = { duration = .2 }
	})
```

- Animated values feed props directly and are derived with `:map`: `Position = styles.alpha:map(function(alpha: number) return UDim2.fromScale(.5, .45):Lerp(UDim2.fromScale(.5, .5), alpha) end)`.
- `React.joinBindings` for combined position and size.
- **House rule on every `CanvasGroup`** so faded UI cannot be clicked: `Interactable = styles.transparency:map(function(transparency: number) return transparency ~= 1 end)`.

### 10.8 Layout and theming

- Scale-only `UDim2` values, three-decimal precision (`UDim2.new(0.152, 0, 0.078, 0)`), plus a `UIAspectRatioConstraint` on most elements as the responsive strategy.
- Converter-emitted prop order and precision are left as-is; hand-added props are appended after with trailing commas.
- **One shared theme module** (`Interface/Tokens`, ruled 2026-07-30) holds colours, fonts, spacing and repeated style compositions; components consume it and never inline visual values.

**Exceptions:** none.
Related: [[Standards/code-style-overview]] [[Standards/code-style-knit-service-layout]] [[Standards/code-style-formatting]]
