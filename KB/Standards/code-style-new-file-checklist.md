---
type: standard
date: 2026-09-20
session: 14e4b904
description: Code style section 14: the annotated skeleton every new file follows and the pre-PR checklist against the ratified rules.
tags: [code-style, luau, checklist]
---
# Code style §14: the new-file checklist
Up: [[Standards]]

**Rule:** Every new file is written against the skeleton below and checked against the ratified rules of §0.1 before a PR is opened.

**Why:** The skeleton encodes §1 through §9 in one place, so a file that matches it is already most of the way to passing review.

**How to apply:**

```lua
--[[                                        <- 4-5 lines of prose, wrapped at 80 columns,
    <what this module is>                      saying what the file IS and nothing else (§2.1)
--]]
                                            <- blank line
--!strict
local <Service> = game:GetService("...")    <- alphabetical-ish, one per line
local Packages = ReplicatedStorage.Packages <- glued to the same block
                                            <- blank
local Knit = require(Packages.Knit)         <- wally requires, Knit first
                                            <- blank
local Policy = require(ReplicatedStorage.Shared.Modules.Net.Policy)   <- the inbound pipeline
local Guards = require(ReplicatedStorage.Shared.Modules.Net.Guards)
local Schemas = require(ReplicatedStorage.Shared.Modules.Net.Schemas.Domain)
                                            <- blank
local Root = ...                            <- first-party requires, BARE unless the annotation is true (§3.3)
local Helper = require(Root.Functions.Helper)
                                            <- blank
local Assets: Folder = ...:WaitForChild("Assets")   <- typed instance handles (boot-time wait, §11.1)
                                            <- blank
local TIMEOUT: number = require(ReplicatedStorage.Shared.Config.Domain.Thing).timeout
                                            <- SCREAMING_SNAKE, typed, read from Config
                                            <- blank
local Types = require(ReplicatedStorage.Shared.Config.Types.Domain)
                                            <- BARE. An annotation here replaces the module
type Thing = Types.Thing                       type and the aliases below stop resolving (§3.2)
                                            <- blank
local Service = Knit.CreateService({
	Name = "ThingService",                  <- equals the file name
	Client = {
		state = Knit.CreateProperty({}) -- what it carries
	},

	Policy = {
		doThing = {rate = DO_RATE, burst = DO_BURST, guards = {Guards.alive}, schema = Schemas.doThing}
	},

	_otherService = nil, -- Resolved in KnitInit
	_registry = {} :: {[string]: Thing}
})

--[[
    <what this does and why>
--]]
                                            <- BLANK LINE before function
function Service:doThing(reference: string, slot: number) : (boolean, string | nil)
	if not self._registry[reference] then
		return false, `Unknown reference: {reference}`
	end

	-- 1) Lock
	-- 2) Mutate
	-- 3) Publish
	...
end

function Service.Client:doThing(player: Player, reference: string, slot: number) : (boolean, string | nil)
	return Service:doThing(reference, slot)
end

function Service:KnitStart() end
function Service:KnitInit()
	self.Client.state:SetTop({})
	self._otherService = Knit.GetService("OtherService")
end

return Service
```

Before opening the PR, check the file against §0.1: no bare literal arguments, no `_G`, no hardcoded tunables, no duplicated predicate, nothing yielding that should return a Promise, every `Client` function has a `Policy` entry, every connection it opens has a stated owner and disconnect path, and **no comment anywhere in it records a decision** (no attribution, no date, no ruling, no history; §5.4).

**Exceptions:** files that are not Knit services (classes, single-function modules, UI) drop the service-specific slots but keep the header, strict line, require order, typed constants and doc-comment gap.
Related: [[Standards/code-style-overview]] [[Standards/code-style-sixty-second-version]] [[Standards/code-style-internal-script-layout]]
