--[[
    The wire rules as arithmetic: the bytes any type takes at its least
    and most, the flag bits it adds to the block it sits in and the side
    array slots it can fill, plus the questions the emitter asks of the
    same rules, such as what a length's prefix is and how a discriminant
    is carried
--]]

--!strict
local Sizes = {}

local Primitives = require("../Config/Primitives")
local Roblox = require("../Config/Roblox")
local Schema = require("../Config/Types/Schema")
local Unions = require("./Unions")
local Wire = require("../Config/Wire")

type Field = Schema.Field
type Pack = Schema.Pack
type Range = Schema.Range
type Roblox = Schema.Roblox
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration
type Variant = Schema.Variant

export type Size = { min: number, max: number, bits: number, slots: number }

-- The bytes a Roblox type's component takes when the type names none
local COMPONENT_BYTES: number = Primitives[Wire.component].bytes :: number
local DICTIONARY_BYTES: number = Wire.dictionaryBytes

-- What each named type's contents take per level, so a tree with two references to itself costs one walk per level
local Contents: { [TypeDeclaration]: { [number]: Size } } = setmetatable({}, { __mode = "k" }) :: any

Sizes.resolved = Unions.resolved

function Sizes.fixed(bytes: number): Size
	return { min = bytes, max = bytes, bits = 0, slots = 0 }
end

function Sizes.isPrimitive(node: Type, name: string): boolean
	local actual: Type = Sizes.resolved(node)
	return actual.kind == "primitive" and actual.name == name
end

-- Whether a named type is @dictionary, so every value of it travels as its id
function Sizes.dictionary(target: TypeDeclaration): boolean
	return target.attributes ~= nil and target.attributes.dictionary == true
end

--[[
    Whether a named type is generated as one function pair that every
    reference calls, rather than inlined at each: when it is exported,
    referenced more than once or recursive, and never when it is @dictionary
--]]

function Sizes.shared(target: TypeDeclaration): boolean
	return not Sizes.dictionary(target) and (target.export or target.depth ~= nil or (target.references or 0) > 1)
end

--[[
    The smallest unsigned prefix that holds a span of lengths
--]]

local function width(span: number): number
	return span <= 255 and 1 or span <= 65535 and 2 or span <= 2 ^ 24 - 1 and 3 or 4
end

--[[
    The prefix bytes and the count bounds of a length: no prefix for an
    exact length, and the u16 default when nothing is declared
--]]

function Sizes.lengths(range: Range?): (number, number, number)
	if not range then
		return 2, 0, Wire.defaultLength
	end

	local low: number = range.min or 0
	local high: number = range.max or Wire.defaultLength

	return low == high and 0 or width(high - low), low, high
end

--[[
    The flag bits a discriminant takes, or the bytes it takes instead once
    there are too many variants for a byte
--]]

function Sizes.discriminant(count: number): (number, number)
	if count > 256 then
		return 0, 2
	end

	local bits: number = 0
	while 2 ^ bits < count do
		bits += 1
	end

	return bits, 0
end

-- How wide a message id is on the wire, from how many ids the direction carries
function Sizes.idBytes(count: number): number
	return count > Wire.idsPerByte and 2 or 1
end

--[[
    A size laid out as its own block: the flag bytes its bits need, then
    its bytes
--]]

function Sizes.block(size: Size): (number, number)
	local flags: number = math.ceil(size.bits / 8)
	return flags + size.min, flags + size.max
end

local function fields(list: { Field }, level: number?): Size
	local total: Size = Sizes.fixed(0)
	for _, field: Field in list do
		local size: Size = Sizes.size(field.type, level)

		total.min += size.min
		total.max += size.max
		total.bits += size.bits
		total.slots += size.slots
	end
	return total
end

--[[
    One of several bodies behind a discriminant, each body a block of its
    own, so a value pays only for the variant it carries
--]]

local function choice(bodies: { Size }): Size
	local bits: number, bytes: number = Sizes.discriminant(#bodies)
	local size: Size = { min = math.huge, max = 0, bits = bits, slots = 0 }

	for _, body: Size in bodies do
		local low: number, high: number = Sizes.block(body)

		size.min = math.min(size.min, low)
		size.max = math.max(size.max, high)
		size.slots = math.max(size.slots, body.slots)
	end

	size.min = (#bodies == 0 and 0 or size.min) + bytes
	size.max += bytes

	return size
end

--[[
    A length prefix and then a run of entries, each entry a block
--]]

local function repeated(range: Range?, entry: Size): Size
	local prefix: number, low: number, high: number = Sizes.lengths(range)
	local entryLow: number, entryHigh: number = Sizes.block(entry)

	return {
		min = prefix + low * entryLow,
		max = prefix + high * entryHigh,
		bits = 0,
		slots = high * entry.slots,
	}
end

--[[
    A Roblox type by its row: a value built from components as each one's
    argument, a CFrame or a Ray as three of its first argument and three of
    its second, a Region3 as six, a rotation-first CFrame as its rotation's
    bytes and the position, an instance as a slot, an enum item as its name
    and two bytes, and the rest as their fixed bytes
--]]

local function roblox(node: Roblox): Size
	local row = Roblox[node.name]
	local generics: { Type } = node.generics or {}
	local widths: { number } = {} -- The bytes a number of each type argument takes

	for index: number = 1, row.generics or 0 do
		widths[index] = generics[index] and Sizes.size(generics[index]).min or COMPONENT_BYTES
	end

	if row.axes then
		local arguments: { number } = row.arguments or {}
		local total: number = 0

		for index: number in row.axes do
			total += widths[arguments[index] or 1]
		end

		return Sizes.fixed(total)
	elseif node.name == "CFrame" or node.name == "Ray" then
		return Sizes.fixed(3 * widths[1] + 3 * widths[2])
	elseif node.name == "Region3" then
		return Sizes.fixed(6 * widths[1])
	elseif row.rotation then
		return Sizes.fixed(row.rotation + 3 * widths[1])
	elseif row.slots then
		return { min = 0, max = 0, bits = 0, slots = row.slots }
	elseif node.name == "EnumItem" then
		return { min = 4, max = 3 + Wire.longestEnumName, bits = 0, slots = 0 }
	end

	return Sizes.fixed(row.bytes :: number)
end

-- What a named type's contents take when they sit at a level, walked once per type and level
local function contents(target: TypeDeclaration, level: number): Size
	local levels: { [number]: Size } = Contents[target] or {}
	local size: Size = levels[level] or Sizes.size(target.type, level)

	Contents[target] = levels
	levels[level] = size

	return size
end

--[[
    The bytes a type takes at its least and most, the flag bits it adds to
    the block it sits in, and the most side-array slots it can fill, by the
    wire rules, with a recursive value at the level given, 1 when no
    recursive type holds it. A recursive type's contents sit one level
    deeper than it does, and past its own bound it adds nothing, since no
    value can hold it there. A shared type that is not recursive starts its
    contents over, since its pair calls a recursive pair at level 1. Total
    over any tree the parser produces, resolved or not
--]]

function Sizes.size(node: Type | Pack, level: number?): Size
	if node.kind == "primitive" then
		if node.name == "boolean" then
			return { min = 0, max = 0, bits = 1, slots = 0 }
		elseif node.name == "unknown" then
			return { min = 0, max = 0, bits = 1, slots = 1 }
		elseif node.name == "string" or node.name == "buffer" then
			local prefix: number, low: number, high: number = Sizes.lengths(node.range)
			return { min = prefix + low, max = prefix + high, bits = 0, slots = 0 }
		end

		return Sizes.fixed(Primitives[node.name].bytes :: number)
	elseif node.kind == "roblox" then
		return roblox(node)
	elseif node.kind == "struct" then
		return fields(node.fields, level)
	elseif node.kind == "pack" then
		return fields(node.parameters, level)
	elseif node.kind == "enum" then
		local bodies: { Size } = {}
		for _, variant: Variant in node.variants do
			table.insert(bodies, fields(variant.fields or {}, level))
		end

		return choice(bodies)
	elseif node.kind == "union" then
		local variants: { Variant }? = Unions.flattened(node.members)
		if variants then
			return choice(table.create(#variants, Sizes.fixed(0)))
		end

		local bodies: { Size } = {}
		for _, member: Type in node.members do
			table.insert(bodies, Sizes.size(member, level))
		end

		return choice(bodies)
	elseif node.kind == "optional" then
		local inner: Size = Sizes.size(node.inner, level)

		-- unknown carries its own presence bit, so nil is already a value it can hold
		if Sizes.isPrimitive(node.inner, "unknown") then
			return inner
		end

		local high: number = select(2, Sizes.block(inner))
		return { min = 0, max = high, bits = 1, slots = inner.slots }
	elseif node.kind == "array" then
		if not Sizes.isPrimitive(node.element, "boolean") then
			return repeated(node.range, Sizes.size(node.element, level))
		end

		-- Booleans pack into a bitset, and an exact count of them into the block's own flags
		local prefix: number, low: number, high: number = Sizes.lengths(node.range)
		if prefix == 0 then
			return { min = 0, max = 0, bits = low, slots = 0 }
		end

		return { min = prefix + math.ceil(low / 8), max = prefix + math.ceil(high / 8), bits = 0, slots = 0 }
	elseif node.kind == "map" then
		return repeated(
			node.range,
			fields({
				{ name = "", type = node.key, start = 0, finish = 0 },
				{ name = "", type = node.value, start = 0, finish = 0 },
			}, level)
		)
	elseif node.kind == "set" then
		return repeated(node.range, Sizes.size(node.element, level))
	elseif node.kind == "literal" then
		return Sizes.fixed(0) -- The reader yields the value itself, so nothing is carried
	end

	local target: TypeDeclaration? = node.target
	local at: number = level or 1

	if not target or (target.depth and at > target.depth) then
		return Sizes.fixed(0)
	elseif Sizes.dictionary(target) then
		return Sizes.fixed(DICTIONARY_BYTES)
	end

	local shared: boolean = Sizes.shared(target)
	local inner: number = target.depth and at + 1 or shared and 1 or at
	local size: Size = contents(target, inner)

	-- A shared named type is a block of its own, so its flag bits stay inside its function pair
	if shared then
		local low: number, high: number = Sizes.block(size)
		return { min = low, max = high, bits = 0, slots = size.slots }
	end

	return size
end

-- A @delta event's payload: a mask bit per field of its struct, each field a block that only its bit sends
function Sizes.delta(node: Type | Pack): Size
	local actual: Type | Pack = node.kind == "reference" and Sizes.resolved(node) or node
	if actual.kind ~= "struct" then
		return Sizes.size(actual) -- Refused by analysis, so sized as it is written
	end

	local size: Size = Sizes.fixed(0)
	for _, field: Field in actual.fields do
		local inner: Size = Sizes.size(field.type)

		size.max += select(2, Sizes.block(inner))
		size.bits += 1
		size.slots += inner.slots
	end

	return size
end

return Sizes
