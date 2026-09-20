---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 9: Knit is the only transport, the Policy inbound pipeline (rate limit, guards, schema), the Service.Client wrapper, payload discipline, the nine-layer server-authority stack, snapshot/patch replication, and client-internal decoupling.
tags: [code-style, luau, networking, security]
---
# Code style §9: client-server communication
Up: [[Standards]]

**Rule:** No hand-created remotes; every endpoint is a member of a service's `Client` table with a `Policy` entry; `Service.Client:x` is a thin wrapper under `Service:x`; the client sends only opaque references, indices and quantities; the server re-derives everything and never trusts a client CFrame or Instance.

**Why:** Knit validates nothing, so the house pipeline is what makes auto-exposed remotes safe. The server-authority stack is the high-water mark of Mike's inventory and building code and is the security posture Volt's runtime and wrapper must make easy, not harder.

**How to apply:**

### 9.1 Transport: Knit only

**There is not a single hand-created `RemoteEvent`, `RemoteFunction` or `BindableEvent` anywhere in the game.** Every endpoint is a member of a service's `Client` table, created by Knit and reached by the client through `Knit.GetService`. There is no IDL and no code generation in the game codebase. Three shapes:

| Direction | Mechanism |
|---|---|
| Server to client **state** | `Knit.CreateProperty(default)` in `Client`; `:SetTop(v)` / `:Set(v)` / `:SetFor(player, v)` / `:ClearFor(player)`; client reads with `:Get()`, `:Observe(...)` |
| Server to client **events** | `Knit.CreateSignal()` in `Client`; `:Fire(player, ...)`, `:FireAll(...)`, `:FireFilter(predicate, ...)` for range-limited broadcasts |
| Client to server | `function Service.Client:method(player, ...)`; the client calls `XService:method(...)` and receives a Promise |

- **Use a Property for state, never a signal.** Signals are for one-shot notifications only.
- The endpoint is declared **camelCase** in `Client` so `InventoryService.Client.transfer` lines up with `Service.Client:transfer`.
- **Knit validates nothing.** `Policy.apply(services)` (`Shared/Modules/Net/Policy.lua`, called once in the server bootstrap between `Knit.AddServicesDeep` and `Knit.Start`) wraps every `Client` function with, in this fixed order: a token-bucket rate limit (`os.clock()`), then the endpoint's guards (`Shared/Modules/Net/Guards.lua`: `alive`, `notDowned`, each reading `Shared/Extensions/`), then the payload schema (`osyrisrblx/t`, shapes in `Shared/Modules/Net/Schemas/<Domain>.lua`), then the handler. A failed stage returns `(false, reason)` to the caller and never reaches the handler. A `Client` function with no `Policy` entry is a boot error.
- **A distance check is not a guard** (2026-08-25): a guard is handed only the caller and the payload and cannot resolve a server-side reference to measure against, so distance is checked in the handler through `Shared/Extensions/WithinDistance`.
- Knit's per-service `Middleware` is not used: it cannot see which method it is guarding.
- **No per-instance remotes** (ratified 2026-07-29). Per-instance component traffic goes through the owning service's `Client` methods; the instance is addressed by a server-issued reference in the payload and passes the same `Policy` pipeline.
- **LEGACY, do not write:** `self.Client.x:Fire(...)` without a policy entry on the way in; `Knit:OnStart()` with a colon; a function dropped into `Client` "for now" (there is no private member of `Client`).

### 9.2 The `Service.Client` wrapper

Client-facing methods are **thin wrappers** that delegate to the server implementation, placed immediately beneath the method they proxy, so the same function is callable internally without re-validating. The player is a **named first parameter** and the wrapper closes over `Service` directly:

```lua
function Service:transfer(props: TransferProps) : (boolean, string | nil)
	...
end

function Service.Client:transfer(player: Player, props: TransferProps) : (boolean, string | nil)
	return Service:transfer(props)
end
```

**LEGACY:** `function Service.Client:transfer(_, ...) return self.Server:transfer(...) end`; the underscore hides the player the guards need.

Client side, unwrap the promise at the call site: `return select(2, InventoryService:transfer(props):await())`. `:andThen` is preferred in controllers; `:await()` inside a synchronous UI handler is acceptable. Errors are **returned as values**, never thrown across the boundary.

### 9.3 Payload discipline

**Anything the client sends is an opaque identifier plus an index plus a quantity. Never a stack, never a CFrame the server is expected to trust, never an Instance.**

### 9.4 The server-authority stack

Layer these in order:

1. **Reference indirection.** Containers are addressed by opaque server-issued string references (`` `{player.UserId} Main` ``, `` `{token} Input` ``) resolved through `Service:resolve()`. The client can only name a reference the server registered.
2. **Mutex locking.** Every mutating action locks the affected View(s) with an owner token and a timeout before touching state. `LockPair` orders locks deterministically by reference to avoid deadlock and single-locks when both sides are the same inventory; `LockMany` / `UnlockMany` for three or more. A tick loop that cannot get the lock **skips the tick** rather than blocking. The rationale: if the server lags, a player spams, or a bug is present, players may dupe items.
   ```lua
   local BACKUP_TIMEOUT: number = .25

   	local token: {nil} = {}
   	if not LockPair(source, destination, token) then
   		return false, `Locking Conflict`
   	end
   ```
3. **Adapters.** Every registered container carries an adapter implementing `canInsert` / `canExtract` / `canSwap`. `CanTransfer` runs **both** adapters before any mutation.
4. **Actors plus anticheat.** Every View has an `Actor`: `Actor.player(player)` or `Actor.system("furnace")`. System actors bypass checks (the server has authority); player actors run through `Anticheat/init.lua` then `Checks/<Name>.lua` (alive, distance, UI-open context).
5. **Rollback.** Failed multi-step operations re-insert what they consumed and `warn` if even that fails.
6. **Full server re-derivation for spatial actions.** The client sends `{object, position, rotation, isSnapped, socketRuntimeId, slotId}`; the server re-looks-up the socket by runtime id, re-checks compatibility against the registry, re-quantizes rotation, re-clamps distance from the character root against `registry.maxDistance` with a tolerance, checks occupancy, runs a `GetPartsInPart` collision test, and places using **its own** `finalCFrame`, ignoring the client's.
7. **Shared validators.** Predicates both sides must agree on live in `src/Shared/**` so the *same* `validateDistance` runs client-side for UX and server-side for truth.
8. **Time.** `os.clock()` (CPU time), never `os.time()`, which the client can change.
9. **Cmdr gating.** `Cmdr/Hooks/BeforeRun.lua` resolves the executor's role in the Whiteoak group through a Promise and returns a rejection string or `nil`; Studio and negative UserIds bypass.

### 9.5 Replication: snapshot / patch

For any large replicated table, use two channels rather than re-sending:

```lua
	Client = {
		sendSnapshot = Knit.CreateProperty({}), -- Send whole inventory slots
		sendPatch = Knit.CreateProperty({}) -- Send only modified slots
	},
```

- `sendSnapshot`: full state on join, `:SetFor(player, {...})`.
- `sendPatch`: only the indices an operation touched, built by `Service:sendToClient(players, modifiedSlots)`, each dirty index mapped through `StackToNet(stack)`. Comm serialises tables as-is, so a `nil` in an array collapses it: a patch is `{version, set = {[index]: Slot}, cleared = {index, ...}}`. Cleared slots are listed, never encoded as `false` (**LEGACY, do not write**).
- Read-only registries replicate once with `:SetTop(data)`; the controller caches via `:Observe()`.
- Carry a `version` counter through both paths.

### 9.6 Client-internal decoupling

Mirror the network layer inside the client:
- **`UIBridge`** (a `sleitnick/signal` pair in `Interface/Shared/`, reinstated 2026-07-31) lets non-React code open screens: `UIBridge:toggleScreen("storage", nil, {contents = contents})`.
- **`CharacterController`** publishes `"join" | "spawn" | "death"` so controllers bind and unbind their own connections.

**Exceptions:** none in the game codebase. Volt itself is the IDL and code generator that will sit under the wrapper; its generated modules are the one place remotes are created, by the generated code, never by hand.
Related: [[Standards/code-style-overview]] [[Standards/code-style-knit-service-layout]] [[Decisions/volt-goals]] [[Research/networking-use-case-coverage-list]]
