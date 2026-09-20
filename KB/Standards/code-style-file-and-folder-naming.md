---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 1: exact casing rules, the init.lua folder-module pattern, and the canonical folder taxonomy including where config, extensions and vendored code live.
tags: [code-style, luau, naming]
---
# Code style §1: file and folder naming
Up: [[Standards]]

**Rule:** PascalCase everywhere below `src/`, `.lua` only, filename equals module name, and every tunable lives under a `Config/` leaf.

**Why:** Rojo path casing that differs from disk is a real bug that only builds on Windows; a filename that is the module name is what loader errors and memory categories report; one home per tunable is what makes it findable.

**How to apply:**

### 1.1 Casing rules (exact)

| Thing | Casing | Example |
|---|---|---|
| Realm folders under `src/` | **PascalCase** (ratified 2026-07-29) | `src/Client`, `src/Server`, `src/Shared` |
| Every folder below a realm | **PascalCase** | `Services/`, `Modules/`, `Classes/`, `Interface/`, `Core/Screens/` |
| Module files | **PascalCase** | `InventoryService.lua`, `SpatialHash.lua` |
| Multi-word folders | **PascalCase**, no separators | `ItemDefinitions`, `StarterPlayerScripts` |
| Entry points | fixed names | `init.lua`, `init.server.lua`, `init.client.lua` |
| Extension | **always `.lua`** | never `.luau` |
| Component file names | **exactly the CollectionService tag**, spaces included | `Interactable NPC.lua` for `Tag = "Interactable NPC"` |
| Data/config files mirroring in-game names | spaces allowed | `Dr Pepper.lua`, `Purchase Workers.lua` |

- **Do not adopt** camelCase file names for React generics or utils (an older-repo variant). Every `Interface/` file, including hooks, state stores and templates, is PascalCase.
- **Realm folders are PascalCase on disk and in `dev.project.json`, matching exactly.** Never "fix" casing in one place only.

### 1.2 `init.lua` patterns

`init.lua` turns a folder into a module. Use it whenever a class grows sub-modules:

```
Modules/Classes/Inventory/
├── init.lua                 -- the Inventory class itself
├── Actions/                 -- one file = one verb, returns a bare function
├── Adapters/                -- permission policy objects
├── Anticheat/
│   ├── init.lua
│   └── Checks/IsAlive.lua
├── Functions/               -- pure helpers, one function per file
└── Modules/                 -- private classes only this class uses
```

`init.server.lua` / `init.client.lua` live at the root of the realm they bootstrap and hand the services folder to Knit: `src/Server/init.server.lua` calls `Knit.AddServicesDeep(script.Services)`, hoists `script.Components`, then `Knit.Start({ServicePromises = true}):catch(error)` (§8.4).

### 1.3 Canonical folder taxonomy

- **A module may never be named after an `Instance` member** (found by booting, 2026-08-25). An Instance's own members outrank a child of the same name on dot access **and** bracket indexing, so `Actions.Remove` and `Actions["Remove"]` both return the deprecated `Instance:Remove` and never the ModuleScript. `Remove`, `Clone`, `Destroy`, `Parent`, `Name`, `Archivable` and the rest of the Instance API are unusable as module names this way. An existing `Actions/Remove.lua` is reached with `Root.Actions:FindFirstChild("Remove")`, which is the ratified instance-lookup rule anyway (§11.1: `FindFirstChild` everywhere `WaitForChild` is not needed).
- **Realm root holds the bootstrap; `Services/` holds the framework objects** (`Services/Features/`, `Services/Player/`, `Cmdr/Hooks/`). There is no `Knit/` folder; `Knit.AddServicesDeep(script.Services)` collects `Services/` deep. Each service's `Name` field is written by hand and must equal its ModuleScript's name.
- Services group by domain: `Features/` for gameplay systems, `Player/` for per-player lifecycle. Controllers mirror services exactly.
- Filename **is** the service name: `InventoryService.lua` is required as `Server.Services.Features.InventoryService` and reported as `InventoryService` in loader errors and memory categories.
- Role encoded by suffix: `*Service.lua` (server), `*Controller.lua` (client). Components, classes and UI modules are plain nouns with **no** suffix.
- **Every configurable value lives under a `Config/` leaf**: pure data tables named for what they configure (`Config/Equip.lua`, `Config/Doors.lua`). Nothing tunable is hardcoded in a service, class, component or UI file: cooldowns, radii, timers, limits, respawn windows, damage and thresholds are all read from config. Realm-shared tuning goes in `src/Shared/Config/`, realm-private tuning next to the code that owns it. Stateless helpers go under `Functions/` or `Extensions/`.
- **Shared predicates live in `Shared/Extensions/`**: a facing check, a distance check, an alive check is written once and required, never re-typed per system (§7.3).
- Empty folders and empty modules are **intent markers** for unbuilt features; leave them in place. `src/Client/Components/` is load-bearing even when empty; both bootstraps iterate it.
- Vendored third-party code goes under `Modules/Libraries/` and is never restyled. First-party infrastructure such as the network pipeline (`Shared/Modules/Net/{Policy,Guards,Schemas}`) follows every rule here.

**Exceptions:** vendored code under `Modules/Libraries/` and Wally `Packages/`.
Related: [[Standards/code-style-overview]] [[Standards/code-style-module-and-class-patterns]] [[Standards/code-style-tooling-config-conventions]]
