---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 11: Rojo project file and require roots, the WaitForChild-only-when-needed rule, Aftman pins, Wally manifest and gitignored Packages, selene, StyLua, one-line editor settings, .gitattributes, the branch and PR workflow, and vestigial files to delete.
tags: [code-style, tooling, rojo, wally, git]
---
# Code style §11: tooling config conventions
Up: [[Standards]]

**Rule:** One Rojo project file per place with paths matching disk casing exactly; Aftman for tool pins; Wally with `Packages/` gitignored and `wally.lock` committed; selene with `std = "roblox"`; the StyLua config from §6.1; a one-line `.vscode/settings.json`; `* text=auto eol=lf`; ticket-per-PR branches into `main`.

**Why:** These are the live configs of Mike's game repo (Frontier Zero). Volt is a package, so its concrete values (place ids, manifest name, dependency set) will differ, but the conventions carry over: what is pinned, what is ignored, how lookups are done and how branches are named.

**How to apply:**

### 11.1 Rojo project file and require roots

One project file per place (`Game/dev.project.json`; `default.project.json` deleted) and no dev/prod/test split within a place. Rojo resolves `$path` against the project file's own directory. Shape of the live file:

```json
{
	"name": "Game",
	"servePlaceIds": [<place id>],
	"tree": {
		"$className": "DataModel",
		"ReplicatedStorage": {
			"Packages": { "$path": "../Packages" },
			"Shared": { "$path": "src/Shared" }
		},
		"ServerScriptService": {
			"ServerPackages": { "$path": "../ServerPackages" },
			"Server": { "$path": "src/Server" },
			"Tests": { "$path": "Tests" }
		},
		"StarterPlayer": {
			"$className": "StarterPlayer",
			"StarterPlayerScripts": {
				"$className": "StarterPlayerScripts",
				"Client": { "$path": "src/Client" }
			}
		},
		"Workspace": {
			"$className": "Workspace",
			"$properties": { "StreamingEnabled": true }
		}
	}
}
```

- Dev-only trees (`ServerScriptService/Tests`) stay out of public builds via **publish hygiene**, not a second project file; Rojo never deletes unmanaged instances.
- **Paths must match on-disk casing exactly** (PascalCase realms). Runtime require roots: server `ServerScriptService.Server.<...>`, client `Players.LocalPlayer.PlayerScripts.Client.<...>` (cached once as `local Client`), shared `ReplicatedStorage.Shared.<...>`, packages `ReplicatedStorage.Packages.<...>`.
- **Instance lookup: `WaitForChild` only when needed, `FindFirstChild` everywhere else** (ratified 2026-07-29). "Needed" means the instance may legitimately not exist yet (client boot racing replication); anything already guaranteed present is fetched with `FindFirstChild` or a literal path and nil-handled.
- The place file is a required, gitignored dependency: `rojo build Game/dev.project.json -o "<Name>.rbxlx"` then `rojo serve Game/dev.project.json`, one serve owner at a time per project file.

### 11.2 `aftman.toml`

```toml
[tools]
rojo = "rojo-rbx/rojo@7.7.0"
wally = "UpliftGames/wally@0.3.2"
stylua = "JohnnyMorganz/StyLua@2.5.2"
selene = "Kampfkarren/selene@0.31.0"
wally-package-types = "JohnnyMorganz/wally-package-types@1.6.2"
```

Aftman today, never Foreman; a Rokit swap stays possible (Rokit reads the same file) but nothing depends on it.

### 11.3 `wally.toml`

```toml
[package]
name = "whiteoak-studios/frontier-zero"
version = "0.1.0"
registry = "https://github.com/UpliftGames/wally-index"
realm = "shared"
private = true
```

- **`Packages/` and `ServerPackages/` are gitignored** (ratified 2026-07-29); `wally.lock` is committed and restores them. `DevPackages/` stays ignored.
- Live dependency set of the game (latest-versions directive): Promise, Component, Trove, Signal `^2`, Observers `^0.5`, Sift, Cmdr, React/ReactRoblox `^17.2`, ReactSpring, Echo `^7.8`, ObjectCache; server realm ProfileStore (`lm-loleris/profilestore`); `Knit = "sleitnick/knit@^1.7.0"` as framework and transport; `t = "osyrisrblx/t@^3.1.0"` as the payload validator behind `Policy`. Removed as never required: TableUtil, OctoTree, Waiter, Leaderboard, UILabs. Dropped: `sp33dtyp3r/observer` (per-instance remotes, §9.1).
- `Sift.Dictionary.merge` is the go-to immutable update. `Echo` and `ObjectCache` are Whiteoak's own published packages, library-grade reference material in the same house style; every sound in the game goes through Echo.

### 11.4 `selene.toml`

```toml
std = "roblox"

exclude = ["Packages/**", "ServerPackages/**"]
```

Nothing else.

### 11.5 `stylua.toml`

See §6.1. Enforce it, through `lune run tools/format`.

### 11.6 `.vscode/settings.json`

One line (2026-09-01):

```json
{
	"luau-lsp.sourcemap.rojoProjectFile": "sourcemap.project.json"
}
```

luau-lsp looks for `default.project.json` by default; without this line it generates no sourcemap and warns on nearly every require. Autogeneration stays on (luau-lsp runs `rojo sourcemap --watch` itself); the generated `sourcemap.json` is gitignored. Nothing else belongs here; a diagnostic the house style deliberately trips is silenced at the line with `--!nolint` (for example `--!nolint DeprecatedApi` on `Player:GetRankInGroup`).

### 11.7 `.gitignore`

Place files and lock files, secrets, harness state, sourcemap, and the Wally package folders (`Packages/`, `ServerPackages/`, `DevPackages/`).

### 11.7a `.gitattributes`

```
* text=auto eol=lf
```

One line. `lune run tools/format` and StyLua write LF while `core.autocrlf=true` checks the same files back out as CRLF; without it every format run is a phantom line-ending diff. Added with `git add --renormalize .`. Volt's repo carries this file from day one.

### 11.8 Workflow (ratified 2026-07-29)

ClickUp ticket per PR under the `Whiteoak-Studios` org. Ticketed work branches as `CU-<taskid>_<compactname>_<author>` (for example `CU-868hrnpd2_prototypeinventoryinterface_Michael-Sumner`); non-ticketed rounds and sub-agent branches use `feature/<system>`, `fix/<x>`, `docs/<x>`. Feature branch, PR, merge, with merge commits reading `Merge pull request #N from Whiteoak-Studios/<branch>`. Commit messages are short, imperative or past tense, human. **`main` is the production branch.**

### 11.9 Vestigial files to prune

`package.json` / `package-lock.json` (Docusaurus) and the stock Rojo `README.md` exist in old repos and are unused. Delete them on day one of a new project.

**Exceptions:** the concrete values (place id, manifest name, dependency list) are the game's; Volt sets its own.
Related: [[Standards/code-style-overview]] [[Standards/code-style-formatting]] [[Standards/git-commits-are-manual]]
