---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 12: the table of where current code (redfallOld, oakshire) departs from older repos; always write the Current column, and never cite dawn as precedent.
tags: [code-style, luau, history]
---
# Code style §12: evolution notes, where newer code departs
Up: [[Standards]]

**Rule:** Write the "Current" column. The "Older" column exists so old code can be read, never so it can be reproduced.

**Why:** Mike's seven repos span years of changing habits. Without this table an agent reading an older repo would copy a superseded shape and call it his style.

**How to apply:**

| Topic | Current (`redfallOld` / `oakshire`) | Older (`scrap`, `menu`, `travelers`, `zombie`, `dawn`) |
|---|---|---|
| **Indentation** | Tabs (width 4), Unix LF, StyLua **enforced** | 4 spaces plus CRLF, StyLua configured but never run |
| **`--!strict` position** | After the header block, above the first service | `dawn`: line 1, above the docblock |
| **`--!strict` coverage** | Near-universal, including UI | 10 to 30% of files, absent from all React |
| **Block comment closer** | `--]]` | bare `]]` |
| **TODO marker** | `-- Whiteoak TODO:` | `-- TO:DO` / `-- TO-DO:` plus numbered list |
| **Framework** | **Knit** (2026-08-25): `Knit.CreateService({ ... })` with parens, `Name` = file name, `Client` of properties/signals/methods each with a `Policy` entry, peers by `Knit.GetService` in `KnitInit` | `Knit.CreateService { ... }` without parens, semicolons, local named after the file, `Client` members with no validation |
| **Conditional expressions** | `and`/`or` chains | `if/then/else` expressions |
| **Configurable values** | Read from a named `Config/` module | Literals scattered through services and components |
| **Yielding** | Promise returned; caller awaits only if it must | `CharacterAdded:Wait()` inside a predicate |
| **Character** | Custom character controller planned; `CharacterService` pub/sub is the only lifecycle source | Default Roblox character plus raw `CharacterAdded` / `Humanoid.Died` |
| **World interaction** | The custom Interaction system, server line-of-sight and distance validated | `ProximityPrompt`, removed from the entire game |
| **Metatable class** | `Module.__index = Module`, state inline in `setmetatable` | `setmetatable(self, { __index = table.clone(Module) })` |
| **Service size** | Thin façade; logic in `Modules/Classes/**` with `Actions` / `Functions` / `Adapters` | Monolithic services holding all gameplay logic |
| **Component state** | Per-instance on `self` inside `Construct` | On the class table, shared across instances (**bug**) |
| **Component to service** | `Knit.OnStart():andThen(function() local XService = Knit.GetService("XService") ... end)` | `Knit:OnStart()` with a colon, or `require(...Knit.XService)` by path |
| **React mounting** | One root, `createPortal` into PlayerGui, `ResetOnSpawn = false` | One `ScreenGui` plus root per controller inside `observeCharacter` |
| **React file naming** | PascalCase throughout `Interface/` | camelCase for generics and utils |
| **React registration** | Zero-boilerplate auto-mount via `App.lua` plus `AppProviders` | Manual mount per controller |
| **Cross-controller UI drive** | `UIBridge` (Signal pair) plus Screens context injectProps | `forwardRef` plus `useImperativeHandle` on a custom `Ref` prop |
| **Client to UI state bridge** | Plain-Lua `State/*` stores plus `Hooks/*` | Custom `Property` observable; direct `.Changed` in components |
| **Async style** | Promises, `:andThen` / `:await()`, observation teardown closures | `repeat task.wait() until cond` spin-waits (**avoid**) |
| **Truthiness** | `if not success then` | explicit `== true` / `== false` in UI code |
| **Replication of large tables** | Snapshot plus patch (`sendSnapshot` / `sendPatch` plus `StackToNet`) | `RemoteTables` monkey-patch on Comm's `RemoteProperty` (do not reintroduce a monkey-patch) |
| **Validation posture** | Reference indirection, mutex, adapters, actors, anticheat, full server re-derivation | Thin or absent; client-authoritative progression |
| **File extension** | `.lua` | mixed `.lua` and `.luau` |

**`dawn` is historical context only.** Its good *ideas* (success-tuple returns, one storage class behind every container, builder DSLs, the gated `Logger`) survive into `redfallOld`. Its *style* (line-1 `--!strict`, three coexisting Knit constructor syntaxes, accidental globals, mixed `,`/`;`, mixed CRLF/LF within one file, `: table`) does not. Never cite `dawn` as precedent.

**Exceptions:** none.
Related: [[Standards/code-style-overview]] [[Standards/code-style-do-not-copy-list]]
