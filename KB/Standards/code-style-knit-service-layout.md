---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 8: thin Knit services and controllers, the exact service table skeleton, KnitInit/KnitStart usage, the twin bootstraps with Policy.apply, sleitnick Components, and the connection-hygiene review gate.
tags: [code-style, luau, knit, lifecycle]
---
# Code style §8: Knit service and controller layout
Up: [[Standards]]

**Rule:** Services and controllers are thin orchestration created by `Knit.CreateService({ ... })` with `Name` equal to the file name, a `Client` table of deliberate endpoints each with a `Policy` entry, peers as `_camelCase` fields resolved in `KnitInit`; `Policy.apply` runs once in the bootstrap; every connection has an owner and a documented disconnect path.

**Why:** The framework is Knit (settled 2026-08-25) with its bundled Comm for networking. Knit exposes every `Client` member as a remote with no check and binds every handler before the first `KnitInit`, which is why the policy pipeline runs in the bootstrap. Volt's wrapper is meant to replace Knit; until Mike rules on its shape, these conventions describe the service layer it must support.

**How to apply:**

### 8.1 Philosophy

**Services and controllers are thin. All real logic lives in `Modules/Classes/**`.** A service resolves references, enforces the network boundary, delegates to a class, and replicates the result. If a service file is growing branching logic, the logic belongs in an `Action`. Keep RunService loops in the module that owns the behaviour. **No god-object managers.**

### 8.2 The skeleton

```lua
local Service = Knit.CreateService({
	Name = "InventoryService", -- Always equal to the file name

	Client = {
		sendSnapshot = Knit.CreateProperty({}), -- Send whole inventory slots
		sendPatch = Knit.CreateProperty({}), -- Send only modified slots
		changed = Knit.CreateSignal() -- One-shot notifications only, never state
	},

	Policy = {
		transfer = {rate = TRANSFER_RATE, burst = TRANSFER_BURST, guards = {Guards.alive}, schema = Schemas.transfer}
	},

	_characterService = nil, -- Resolved in KnitInit
	_profiles = {} :: {[Player]: View}, -- List of player inventory profiles
	_registry = {} :: {[Reference]: View}
})
```

- The local is **always named for its role**: `Service`, `Controller`. Never named after the file.
- `Name` is written by hand and **is** the file name.
- `Client` holds the inbound handlers (methods) and the outbound properties and signals. **Anything in `Client` is a remote**, so nothing goes in it that is not a deliberate endpoint with a `Policy` entry.
- `Policy` is a plain table (per endpoint: rate limit, guard list, payload schema), read once by the bootstrap's `Policy.apply` (§8.4, §9.1), never from `KnitInit`.
- Peers are fields declared in the table (`_characterService = nil`) and resolved with `Knit.GetService` in `KnitInit`.
- **Controllers do not declare `Client`**: `Knit.CreateController({ Name = "InventoryController" })`. Server-to-client listeners are `InventoryService.changed:Connect(...)` and `InventoryService.sendPatch:Observe(...)` on the proxy from `Knit.GetService`, registered in `KnitInit`, disconnected by the controller's `Trove` (§8.6).
- File ends `return Service` / `return Controller`.
- **LEGACY, do not write:** `Knit.CreateService { ... }` without parens, semicolon table separators, the local named after the file, `:: RemoteEvent` casts on signals, `Client = {}` on a controller.

### 8.3 Lifecycle usage

- **`KnitInit`**, in this order: `:SetTop()` every `Client` property, resolve peers with `Knit.GetService`, register player-observation bindings (§8.6), build registries. **`Policy.apply` is NOT called here** (2026-08-25): Knit binds every remote before the first `KnitInit` and Comm captures the handler as it binds, so a wrapper installed here would police nothing. Almost all setup lives here. **Must not yield**: Knit runs every `KnitInit` in sequence, so one yield stalls the boot for every service behind it.
- **`KnitStart`**: only work that requires every other service to already exist (mounting the React root, starting loops that call peers).
- Both are always present; the empty one is a one-liner and goes first (§4.2).
- `Knit.Start()` rejects on the first `KnitInit` error; the bootstrap's `:catch(error)` turns that into a hard boot failure. A half-initialised server is worse than a dead one.

### 8.4 Bootstrap (both realms, near-identical twins)

```lua
local services: {any} = Knit.AddServicesDeep(script.Services)

-- Every endpoint is policed before Knit binds it as a remote, because Comm
-- captures the handler at bind time and that happens before the first KnitInit
Policy.apply(services)

-- Rojo only emits a folder that has something in it, so Components is absent
-- until the first one lands; the hoist is a no-op until then
local components: Instance? = script:FindFirstChild("Components")

for _, instance: Instance in components and components:GetDescendants() or {} do
	if not instance:IsA("ModuleScript") then
		continue
	end

	assert(not Component[instance.Name], `Cannot create component {instance.Name} because Component library has member with the same name!`)
	Component[instance.Name] = require(instance) -- This allows us to quickly access components directly from the Component library.
end

Knit.Start():catch(error) -- The client passes {ServicePromises = true}; the server ignores it
```

- One `AddServicesDeep` / `AddControllersDeep` per realm collects the folder deep, then `Knit.Start` runs every `KnitInit` and `task.spawn`s every `KnitStart`. `ServicePromises = true` belongs on the **client** (its only reader is `KnitClient.lua`) and is what makes every service call return a Promise (§9.2).
- **Binding discipline.** `Policy.apply(Knit.AddServicesDeep(script.Services))` is called **in the bootstrap, between collecting the services and `Knit.Start`** (2026-08-25). It asserts that every function in `Client` has a `Policy` entry and every `Policy` entry names one, and errors the boot otherwise. Running it from one place is what makes the check inescapable.
- The Component-hoisting loop is a house idiom on both sides.
- Code that genuinely cannot resolve a service at module scope (components) uses `Knit.OnStart():andThen(...)`; `:catch(error)` (function passed by reference) is the standard terminator on any promise chain.

### 8.5 Components (sleitnick/Component)

```lua
local ComponentModule = require(Packages.Component)

local Component = ComponentModule.new({
	Tag = "Storage Container",
})

function Component:Construct()
	self._trove = Trove.new()
end

function Component:Stop()
	if self._trove then
		self._trove:Destroy()
	end
end
```

- Require is aliased **`ComponentModule`** so the instance can be named `Component`.
- **Tag strings are human-readable with spaces** (`"Build Mode"`, `"Storage Container"`). The file name matches the tag exactly.
- Lifecycle hooks stay PascalCase (`Construct`, `Start`, `Stop`); custom methods are camelCase.
- **All per-instance state goes on `self` inside `Construct`.** State on the class table (`Component._trove = Trove.new()` above `Construct`) is silently shared across every tagged instance; a shipped bug in older repos. **Never do it.**
- Components are outside the loader's lifecycle. A component that needs a service waits for the boot, then resolves it:
  ```lua
  Knit.OnStart():andThen(function()
  	local InventoryService = Knit.GetService("InventoryService")
  	...
  end):catch(error)
  ```
  **LEGACY:** `require(ServerScriptService.Server.Knit.XService)` by path from inside a component.
- **`Stop` is not optional.** Every component that opens anything in `Construct` closes it in `Stop`; the `Trove` makes that one line.

### 8.6 Lifecycle and cleanup libraries

- **Observe-with-teardown**: one idiom replaces raw `PlayerAdded` / `GetPropertyChangedSignal` everywhere. The callback runs once per matching entity or value and **returns the closure that tears down exactly what it set up**, run automatically when it goes away. Implemented by **`sleitnick/observers`** (reinstated 2026-07-31):
  ```lua
  observePlayer(function(player)
  	self:_load(player)

  	return function()
  		self:_release(player)
  	end
  end)
  ```
- **`Trove`** held as `self._trove` / `Controller._trove`, `:Add()`-ing instances, connections and `task.spawn` handles, `:Destroy()`-ed in `Stop()` / `cleanup()` behind an `if self._trove then` guard.
- **Character state pub/sub**: `CharacterService` (server) and `CharacterController` (client) publish `"join" | "spawn" | "death"` to named subscribers, so every other system calls `subscribe(identifier, callback)` instead of re-implementing `CharacterAdded`. This is the **only** character lifecycle source; nothing binds `CharacterAdded` / `Humanoid.Died` directly, because the default Roblox character is not what ships (a custom character controller is planned; until it lands the default character runs behind the Character system's API).

#### Connection hygiene (ratified 2026-07-29)

**Every connection, loop and callback has a named owner and a documented disconnect path. Zero leaks, nothing still running for a player who left.** This is a review gate: a diff that adds a `:Connect` with no visible teardown does not merge.

- **Owner.** A connection belongs to a Trove, which belongs to an object: `self._trove` on a component or class instance, `Controller._trove` on a controller, the player-observation teardown closure for anything per-player. Nothing is connected without an owner.
- **Documented.** Where the teardown is not within a few lines, the comment says where it is: `-- Disconnected by _trove in Stop()`. Any function that starts a loop states in its doc comment what stops it.
- **Loops.** `while task.wait(n) do` bodies check a live flag or token and `break`; the `task.spawn` handle goes into the Trove. A tick loop that cannot take its lock skips the tick rather than blocking (§9.4).
- **Callbacks.** Subscriptions return their own disconnect closure (§7.6) and that closure goes into the Trove. React effects return a cleanup function; a `useEffect` that connects and returns nothing is a bug (§10.4).
- **Per-player state** is cleared in the player-observation teardown: buckets, profiles, caches, pending Promises. A leaked entry keyed by `Player` holds that instance alive for the life of the server.
- Every system's documentation states its own cleanup contract. If the note and the code disagree, one of them is wrong and it is fixed in the same branch.

**Exceptions:** none.
Related: [[Standards/code-style-overview]] [[Standards/code-style-internal-script-layout]] [[Standards/code-style-client-server-communication]] [[Decisions/volt-goals]]
