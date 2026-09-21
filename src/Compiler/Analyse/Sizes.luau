--[[
    The wire rules as arithmetic: the bytes any type takes at its least
    and most, the flag bits it adds to the block it sits in and the side
    array slots it can fill, plus the questions the emitter asks of the
    same rules, such as what a length's prefix is, how a discriminant is
    carried, and which runtime classes a union member can be
--]]

--!strict
local Sizes = {}

local Primitives = require("../Config/Primitives")
local Roblox = require("../Config/Roblox")
local Schema = require("../Config/Types/Schema")
local Wire = require("../Config/Wire")

type Field = Schema.Field
type Pack = Schema.Pack
type Range = Schema.Range
type Roblox = Schema.Roblox
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration
type Variant = Schema.Variant

export type Size = { min: number, max: number, bits: number, slots: number }

-- Named types being sized right now, so a reference back into one stops
local visiting: { [TypeDeclaration]: boolean } = {}

-- The bytes a vector or CFrame component takes when the type names none
local COMPONENT_BYTES: number = Primitives[Wire.component].bytes :: number
local COMPONENT: Size = { min = COMPONENT_BYTES, max = COMPONENT_BYTES, bits = 0, slots = 0 }

function Sizes.fixed(bytes: number): Size
	return { min = bytes, max = bytes, bits = 0, slots = 0 }
end

--[[
    Follows references to the type they name, so a rule about what a value
    is at runtime sees through named types
--]]

function Sizes.resolved(node: Type): Type
	while node.kind == "reference" and node.target do
		node = node.target.type
	end
	return node
end

function Sizes.isPrimitive(node: Type, name: string): boolean
	local actual: Type = Sizes.resolved(node)
	return actual.kind == "primitive" and actual.name == name
end

-- Two unit enums in one union flatten their variants into one discriminant, so they never clash
function Sizes.isUnitEnum(node: Type): boolean
	local actual: Type = Sizes.resolved(node)
	return actual.kind == "enum" and actual.tag == nil
end

--[[
    Whether a named type is generated as one function pair that every
    reference calls, rather than inlined at each: when it is exported or
    referenced more than once
--]]

function Sizes.shared(target: TypeDeclaration): boolean
	return target.export or (target.references or 0) > 1
end

--[[
    The variants of a union whose members are all unit enums, which
    flatten into one discriminant, or nil when any member is not one
--]]

function Sizes.flattened(members: { Type }): { Variant }?
	local variants: { Variant } = {}
	for _, member: Type in members do
		local actual: Type = Sizes.resolved(member)
		if actual.kind ~= "enum" or actual.tag then
			return nil
		end
		table.move(actual.variants, 1, #actual.variants, #variants + 1, variants)
	end
	return variants
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

--[[
    A size laid out as its own block: the flag bytes its bits need, then
    its bytes
--]]

function Sizes.block(size: Size): (number, number)
	local flags: number = math.ceil(size.bits / 8)
	return flags + size.min, flags + size.max
end

local function fields(list: { Field }): Size
	local total: Size = Sizes.fixed(0)
	for _, field: Field in list do
		local size: Size = Sizes.size(field.type)

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
    A Roblox type by its row: a vector as its components, a CFrame as three
    position and three rotation components, an aligned one as a byte and
    the position, an instance as a slot, an enum item as its name and two
    bytes, and the rest as their fixed bytes
--]]

local function roblox(node: Roblox): Size
	local row = Roblox[node.name]
	local generics: { Type } = node.generics or {}
	local component: Size = generics[1] and Sizes.size(generics[1]) or COMPONENT

	if row.axes then
		return Sizes.fixed(#row.axes * component.min)
	elseif node.name == "CFrame" then
		local rotation: Size = generics[2] and Sizes.size(generics[2]) or COMPONENT
		return Sizes.fixed(3 * component.min + 3 * rotation.min)
	elseif node.name == "AlignedCFrame" then
		return Sizes.fixed(1 + 3 * component.min)
	elseif row.slots then
		return { min = 0, max = 0, bits = 0, slots = row.slots }
	elseif node.name == "EnumItem" then
		return { min = 4, max = 3 + Wire.longestEnumName, bits = 0, slots = 0 }
	end

	return Sizes.fixed(row.bytes :: number)
end

--[[
    The bytes a type takes at its least and most, the flag bits it adds to
    the block it sits in, and the most side-array slots it can fill, by the
    wire rules. Total over any tree the parser produces, resolved or not
--]]

function Sizes.size(node: Type | Pack): Size
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
		return fields(node.fields)
	elseif node.kind == "pack" then
		return fields(node.parameters)
	elseif node.kind == "enum" then
		local bodies: { Size } = {}
		for _, variant: Variant in node.variants do
			table.insert(bodies, fields(variant.fields or {}))
		end

		return choice(bodies)
	elseif node.kind == "union" then
		local variants: { Variant }? = Sizes.flattened(node.members)
		if variants then
			return choice(table.create(#variants, Sizes.fixed(0)))
		end

		local bodies: { Size } = {}
		for _, member: Type in node.members do
			table.insert(bodies, Sizes.size(member))
		end

		return choice(bodies)
	elseif node.kind == "optional" then
		local inner: Size = Sizes.size(node.inner)

		-- unknown carries its own presence bit, so nil is already a value it can hold
		if Sizes.isPrimitive(node.inner, "unknown") then
			return inner
		end

		local high: number = select(2, Sizes.block(inner))
		return { min = 0, max = high, bits = 1, slots = inner.slots }
	elseif node.kind == "array" then
		if not Sizes.isPrimitive(node.element, "boolean") then
			return repeated(node.range, Sizes.size(node.element))
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
			})
		)
	elseif node.kind == "set" then
		return repeated(node.range, Sizes.size(node.element))
	end

	local target: TypeDeclaration? = node.target
	if not target or visiting[target] then
		return Sizes.fixed(0)
	end

	visiting[target] = true

	local size: Size = Sizes.size(target.type)
	visiting[target] = nil

	-- A shared named type is a block of its own, so its flag bits stay inside its function pair
	if Sizes.shared(target) then
		local low: number, high: number = Sizes.block(size)
		return { min = low, max = high, bits = 0, slots = size.slots }
	end

	return size
end

--[[
    The runtime classes a union member can be, through references and
    nested unions, which is what the writer tells members apart by
--]]

function Sizes.classes(node: Type): { string }
	local actual: Type = Sizes.resolved(node)

	if actual.kind == "union" then
		local list: { string } = {}
		for _, member: Type in actual.members do
			for _, class: string in Sizes.classes(member) do
				table.insert(list, class)
			end
		end

		return list
	elseif actual.kind == "primitive" then
		local name: string = actual.name
		local named: boolean = name == "boolean" or name == "string" or name == "buffer" or name == "unknown"

		return { named and name or "number" }
	elseif actual.kind == "roblox" then
		return { Roblox[actual.name].class }
	elseif actual.kind == "enum" then
		return { actual.tag and "table" or "string" }
	elseif actual.kind == "optional" then
		return { "nil" }
	elseif actual.kind == "reference" then
		return {} -- Unresolved, and already reported
	end

	return { "table" }
end

return Sizes
