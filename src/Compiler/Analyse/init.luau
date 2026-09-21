--[[
    Checks every resolved type against the wire rules, gives each message
    an id per direction, refuses an unreliable event that cannot fit one
    fire, and hashes the canonical print of the file. The sizes and the
    print come from the sibling files, reached through the folder's name
    because an init file stands for its folder
--]]

--!strict
local Analyse = {} :: any
Analyse.__index = Analyse

local Diagnostics = require("./Diagnostics")
local Parser = require("./Parser")
local Primitives = require("./Config/Primitives")
local Print = require("./Analyse/Print")
local Roblox = require("./Config/Roblox")
local Schema = require("./Config/Types/Schema")
local Sizes = require("./Analyse/Sizes")

type Declaration = Schema.Declaration
type Diagnostics = Diagnostics.Diagnostics
type Event = Schema.Event
type File = Schema.File
type Pack = Schema.Pack
type Range = Schema.Range
type Roblox = Schema.Roblox
type Size = Sizes.Size
type Type = Schema.Type

local COUNTS: { string } = { "one", "two" }

-- How each runtime class reads in an ambiguity message
local CLASSES: { [string]: string } = {
	number = "numbers",
	string = "strings",
	buffer = "buffers",
	boolean = "booleans",
	table = "tables",
	Instance = "instances",
}

local FNV_OFFSET: number = 2166136261
local FNV_PRIME_LOW: number = 403 -- The prime 16777619 is 2^24 + 403; the split keeps every product exact
local WORD: number = 2 ^ 32

--[[
    The bounds a range declares, without the nil of a missing end
--]]

local function ends(range: Range): { number }
	local list: { number } = {}
	if range.min then
		table.insert(list, range.min)
	end
	if range.max then
		table.insert(list, range.max)
	end
	return list
end

--[[
    FNV-1a over the bytes of a text, as a 32-bit number
--]]

function Analyse.hash(text: string): number
	local hash: number = FNV_OFFSET
	for index: number = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = (bit32.lshift(hash, 24) + hash * FNV_PRIME_LOW) % WORD
	end
	return hash
end

--[[
    Analyses a resolved file in place: every type checked, every message
    given its ids, every unreliable event held to the budget. Returns the
    schema hash
--]]

function Analyse.file(file: File, diagnostics: Diagnostics): number
	local self = setmetatable({
		_diagnostics = diagnostics,
		_toServer = 0, -- The last id given in each direction
		_toClient = 0,
		_unreliable = {} :: { Event }, -- Checked against the budget once the id widths are known
	}, Analyse)

	self:declarations(file.declarations)
	self:budget(file.options.unreliableBudget :: number)

	return Analyse.hash(Print.file(file))
end

--[[
    Walks the declarations in order, checking each type and giving each
    message the next id in every direction it travels
--]]

function Analyse:declarations(declarations: { Declaration })
	for _, declaration: Declaration in declarations do
		if declaration.kind == "type" then
			self:type(declaration.type)
		elseif declaration.kind == "namespace" then
			self:declarations(declaration.declarations)
		else
			if declaration.data then
				self:type(declaration.data)
			end

			if declaration.kind == "function" then
				if declaration["return"] then
					self:type(declaration["return"])
				end

				declaration.toServer = self:next("_toServer")
				declaration.toClient = self:next("_toClient")
			else
				if declaration.from == "Client" or declaration.from == "Both" then
					declaration.toServer = self:next("_toServer")
				end

				if declaration.from == "Server" or declaration.from == "Both" then
					declaration.toClient = self:next("_toClient")
				end

				if declaration.type == "Unreliable" then
					table.insert(self._unreliable, declaration)
				end
			end
		end
	end
end

function Analyse:next(direction: string): number
	self[direction] += 1
	return self[direction]
end

--[[
    Refuses every unreliable event whose largest message, id included,
    would not fit one fire
--]]

function Analyse:budget(budget: number)
	for _, event: Event in self._unreliable do
		local toServer: number = event.toServer and self._toServer or 0
		local toClient: number = event.toClient and self._toClient or 0
		local idBytes: number = Sizes.idBytes(math.max(toServer, toClient))
		local payload: Size = event.data and Sizes.size(event.data) or Sizes.fixed(0)
		local largest: number = idBytes + select(2, Sizes.block(payload))

		if largest > budget then
			local message: string =
				`event {event.path} can reach {largest} bytes, over the unreliable budget of {budget}`
			self._diagnostics:error("V3010", message, event.spans.type)
		end
	end
end

--[[
    Checks one type node and everything inside it
--]]

function Analyse:type(node: Type | Pack)
	if node.kind == "primitive" then
		self:range(node)
	elseif node.kind == "roblox" then
		self:roblox(node)
	elseif node.kind == "array" then
		self:lengths(node.range)
	elseif node.kind == "map" then
		self:key(node.key, "a map key")
		self:lengths(node.range)
	elseif node.kind == "set" then
		self:key(node.element, "a set element")
		self:lengths(node.range)
	elseif node.kind == "union" then
		self:union(node)
	end

	for _, child: Type in Parser.children(node) do
		self:type(child)
	end
end

--[[
    A primitive's range: mandatory and two-ended on a quantised float,
    refused on a boolean or unknown, a length on a string or buffer, and
    whole and within the bounds on an integer
--]]

function Analyse:range(node: Type)
	local name: string = (node :: any).name
	local range: Range? = (node :: any).range
	local row = Primitives[name]

	if row.levels then
		if not (range and range.min and range.max and range.min < range.max) then
			self._diagnostics:error("V3011", `{name} needs a range with both ends, such as {name}(0..1)`, range or node)
		end

		return
	end

	if not range then
		return
	elseif name == "boolean" or name == "unknown" then
		return self._diagnostics:error("V3011", `{name} takes no range`, range)
	elseif name == "string" or name == "buffer" then
		return self:lengths(range)
	elseif range.min and range.max and range.min > range.max then
		return self._diagnostics:error("V3011", "a range's minimum is above its maximum", range)
	end

	local low: number? = row.min
	local high: number? = row.max

	if not low or not high then
		return -- A float takes any range
	end

	for _, limit: number in ends(range) do
		if limit % 1 ~= 0 then
			return self._diagnostics:error("V3011", `{name}'s range has a fractional end, {limit}`, range)
		elseif limit < low or limit > high then
			local message: string = `{name}'s range is outside its bounds {Print.whole(low)}..{Print.whole(high)}`
			return self._diagnostics:error("V3011", message, range)
		end
	end
end

--[[
    A length range on a string, buffer, array, map or set: whole numbers
    from zero up, in order
--]]

function Analyse:lengths(range: Range?)
	if not range then
		return
	end

	for _, limit: number in ends(range) do
		if limit < 0 or limit % 1 ~= 0 then
			local message: string = `a length must be a whole number of at least 0, got {limit}`
			return self._diagnostics:error("V3011", message, range)
		end
	end

	if range.min and range.max and range.min > range.max then
		self._diagnostics:error("V3011", "a range's minimum is above its maximum", range)
	end
end

--[[
    A Roblox type's arguments: as many numeric primitives as the type
    takes, and a class only on an instance
--]]

function Analyse:roblox(node: Roblox)
	local row = Roblox[node.name]
	local allowed: number = row.generics or 0
	local generics: { Type }? = node.generics

	if generics and #generics ~= allowed then
		local takes: string = allowed == 0 and "no type arguments"
			or `{COUNTS[allowed]} numeric type argument{allowed == 1 and "" or "s"}`
		self._diagnostics:error("V3007", `{node.name} takes {takes}, got {#generics}`, node)
	elseif generics then
		for _, generic: Type in generics do
			if generic.kind ~= "primitive" or not Primitives[generic.name].bytes then
				local message: string =
					`{node.name}'s type argument must be a numeric primitive, got {Print.type(generic)}`
				self._diagnostics:error("V3007", message, generic)
			end
		end
	end

	if node.class and not row.slots then
		self._diagnostics:error("V3007", `{node.name} takes no class`, node)
	end
end

--[[
    A map key or set element must be a value Luau can index a table by
    and the reader can compare for duplicates
--]]

function Analyse:key(node: Type, label: string)
	local actual: Type = Sizes.resolved(node)
	local allowed: boolean = (actual.kind == "primitive" and actual.name ~= "unknown")
		or actual.kind == "roblox"
		or (actual.kind == "enum" and actual.tag == nil)
		or actual.kind == "reference"

	if not allowed then
		local message: string = `{label} must be a primitive, string, enum or Roblox type, got {Print.type(node)}`
		self._diagnostics:error("V3008", message, node)
	end
end

--[[
    Two union members the writer could not tell apart by typeof and shape
    are refused, as is a member that can be nil or anything at all
--]]

function Analyse:union(node: Type)
	local seen: { [string]: Type } = {}

	for _, member: Type in (node :: any).members do
		for _, class: string in Sizes.classes(member) do
			local first: Type? = seen[class]

			if class == "nil" then
				local message: string =
					`union member {Print.type(member)} is optional; make the whole union optional instead`
				self._diagnostics:error("V3009", message, member)
			elseif class == "unknown" then
				self._diagnostics:error("V3009", "unknown cannot be a union member; it already takes any value", member)
			elseif first and not (Sizes.isUnitEnum(first) and Sizes.isUnitEnum(member)) then
				local both: string = CLASSES[class] or `{class} values`
				local message: string =
					`union members {Print.type(first)} and {Print.type(member)} are both {both} at runtime`
				self._diagnostics:error("V3009", message, member)
			end

			seen[class] = first or member
		end
	end
end

return Analyse
