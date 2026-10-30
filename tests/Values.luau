--[[
    Values for the round-trip tests: one of any type at its least, its
    most or at random within what the wire holds, and the comparison
    that says whether a value read back matches the one written, exactly
    for most types and within the precision the wire has for the rest
--]]

--!strict
local RobloxValues = require("./RobloxValues")
local Primitives = require("@volt/Compiler/Config/Primitives")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Sizes = require("@volt/Compiler/Analyse/Sizes")

type Field = Schema.Field
type Type = Schema.Type
type Variant = Schema.Variant

local FREE_LENGTH: number = 100 -- As long as an unbounded string, buffer or list gets in a test
local FLOAT_REACH: { [string]: number } = { f16 = 65504, f32 = 2 ^ 20, f64 = 2 ^ 40 } -- How far a random float goes each way

-- The least and most code point of a UTF-8 character of each width in bytes
local CODE_POINTS: { { number } } = { { 0, 0x7F }, { 0x80, 0x7FF }, { 0x800, 0xFFFF }, { 0x10000, 0x10FFFF } }
local SURROGATES: { number } = { 0xD800, 0xDFFF } -- The code points UTF-8 never encodes

local Values = {}

local near: (Type, any, any) -> boolean
local valueOf: (Type, string?) -> any

-- The least and most a number of a type may be
local function bounds(node: any): (number, number)
	local reach: number = FLOAT_REACH[node.name] or 0
	local row = Primitives[node.name]
	local range = node.range

	return range and range.min or row.min or -reach, range and range.max or row.max or reach
end

local function randomBytes(count: number): string
	local bytes: { string } = {}
	for index: number = 1, count do
		bytes[index] = string.char(math.random(0, 255))
	end
	return table.concat(bytes)
end

-- Valid UTF-8 of exactly a count of bytes, its characters of every width at random
local function randomText(count: number): string
	local characters: { string } = {}
	local left: number = count

	while left > 0 do
		local width: number = math.random(1, math.min(left, #CODE_POINTS))
		local point: number = math.random(CODE_POINTS[width][1], CODE_POINTS[width][2])

		if point < SURROGATES[1] or point > SURROGATES[2] then
			table.insert(characters, utf8.char(point))
			left -= width
		end
	end

	return table.concat(characters)
end

-- The first, the last or any entry of a list
local function pick(list: { any }, ends: string?): any
	return ends == "min" and list[1] or ends == "max" and list[#list] or list[math.random(#list)]
end

-- How many entries or bytes a length takes at an end or at random, within what a test can afford
local function lengthOf(range: any, ends: string?): number
	local _, low: number, high: number = Sizes.lengths(range)
	high = math.min(high, FREE_LENGTH)

	return ends == "min" and low or ends == "max" and high or math.random(low, high)
end

--[[
    A value of a primitive: its least or most when an end is asked for,
    or one at random within its bounds
--]]

local function primitiveOf(shape: any, ends: string?): any
	local name: string = shape.name
	if name == "boolean" then
		if ends then
			return ends == "max"
		end

		return math.random() < 0.5
	elseif name == "unknown" then
		if ends == "min" then
			return nil
		end

		return ends == "max" and { 1 } or pick({ nil, 5, "text", {} }, nil)
	elseif name == "string" or name == "buffer" then
		local count: number = lengthOf(shape.range, ends)
		local text: string = shape.utf8 and randomText(count) or randomBytes(count)

		return name == "buffer" and buffer.fromstring(text) or text
	end

	local low: number, high: number = bounds(shape)

	if ends then
		return ends == "min" and low or high
	elseif Primitives[name].min then
		return low + math.floor(math.random() * (high - low))
	end

	return low + math.random() * (high - low)
end

--[[
    A value of any type: its least or most when an end is asked for, or
    one at random; a list takes its length the same way
--]]

function valueOf(node: Type, ends: string?): any
	local shape: any = Sizes.resolved(node)
	local kind: string = shape.kind

	if kind == "primitive" then
		return primitiveOf(shape, ends)
	elseif kind == "literal" then
		return shape.value
	elseif kind == "roblox" then
		return RobloxValues.valueOf(shape, ends, Values)
	elseif kind == "struct" then
		local value: { [string]: any } = {}
		for _, field: Field in shape.fields do
			value[field.name] = valueOf(field.type, ends)
		end
		return value
	elseif kind == "optional" then
		if ends == "max" or (ends == nil and math.random() < 0.5) then
			return valueOf(shape.inner, ends)
		end
		return nil
	elseif kind == "enum" then
		local variant: Variant = pick(shape.variants, ends)
		if not shape.tag then
			return variant.name
		end

		local value: { [string]: any } = { [shape.tag] = variant.name }
		for _, field: Field in (variant.fields or {}) :: { Field } do
			value[field.name] = valueOf(field.type, ends)
		end
		return value
	elseif kind == "union" then
		return valueOf(pick(shape.members, ends), ends)
	elseif kind == "array" then
		local count: number = lengthOf(shape.range, ends)
		local value: { any } = table.create(count)
		for index: number = 1, count do
			value[index] = valueOf(shape.element, ends)
		end
		return value
	end

	-- A map or set: keys are drawn at random until enough differ
	local count: number = lengthOf(shape.range, ends)
	local key: Type = kind == "set" and shape.element or shape.key
	local value: { [any]: any } = {}
	local filled: number = 0

	while filled < count do
		local entry: any = valueOf(key, nil)
		if value[entry] == nil then
			value[entry] = kind == "set" and true or valueOf(shape.value, ends)
			filled += 1
		end
	end

	return value
end

--[[
    Whether a value read back matches the one written: exactly for most
    types, within the precision the wire has for halves, singles and
    quantised floats, and entry by entry through composites
--]]

function near(node: Type, expected: any, actual: any): boolean
	local shape: any = Sizes.resolved(node)
	local kind: string = shape.kind
	local name: string = shape.name

	if kind == "roblox" then
		return RobloxValues.near(shape, expected, actual, Values)
	elseif kind == "literal" then
		return expected == shape.value and actual == shape.value
	elseif kind == "struct" then
		for _, field: Field in shape.fields do
			if not near(field.type, expected[field.name], actual[field.name]) then
				return false
			end
		end

		return true
	elseif kind == "optional" then
		if expected == nil or actual == nil then
			return expected == actual
		end

		return near(shape.inner, expected, actual)
	elseif kind == "enum" then
		if not shape.tag then
			return expected == actual
		end

		for _, variant: Variant in shape.variants do
			if variant.name == expected[shape.tag] then
				local body: Type = { kind = "struct", fields = variant.fields or {}, start = 0, finish = 0 }
				return expected[shape.tag] == actual[shape.tag] and near(body, expected, actual)
			end
		end

		return false
	elseif kind == "union" then
		for _, member: Type in shape.members do
			local ok: boolean, same: any = pcall(near, member, expected, actual)
			if ok and same then
				return true
			end
		end

		return false
	elseif kind == "array" then
		if #expected ~= #actual then
			return false
		end

		for index: number, entry: any in expected do
			if not near(shape.element, entry, actual[index]) then
				return false
			end
		end

		return true
	elseif kind == "map" or kind == "set" then
		for key: any, entry: any in expected do
			if actual[key] == nil or (kind == "map" and not near(shape.value, entry, actual[key])) then
				return false
			end
		end

		for key: any in actual do
			if expected[key] == nil then
				return false
			end
		end

		return true
	elseif name == "f16" then
		return math.abs(expected - actual) <= math.abs(expected) / 1024 + 2 ^ -24
	elseif name == "f32" then
		return math.abs(expected - actual) <= math.abs(expected) / 2 ^ 23
	elseif Primitives[name].levels then
		local low: number, high: number = bounds(shape)
		return math.abs(expected - actual) <= (high - low) / (Primitives[name].levels :: number) / 2 + 1e-9
	elseif name == "buffer" then
		return buffer.tostring(expected) == buffer.tostring(actual)
	end

	return expected == actual
end

Values.valueOf = valueOf
Values.near = near
Values.bounds = bounds
Values.pick = pick

return Values
