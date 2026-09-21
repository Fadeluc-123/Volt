--[[
    Values for the round-trip tests: one of any type at its least, its
    most or at random within what the wire holds, and the comparison
    that says whether a value read back matches the one written, exactly
    for most types and within the precision the wire has for the rest
--]]

--!strict
local Environment = require("./Environment")
local Primitives = require("@volt/Compiler/Config/Primitives")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Sizes = require("@volt/Compiler/Analyse/Sizes")
local Wire = require("@volt/Compiler/Config/Wire")

type Field = Schema.Field
type Type = Schema.Type
type Variant = Schema.Variant

local BrickColor = Environment.BrickColor
local CFrame = Environment.CFrame
local Color3 = Environment.Color3
local DateTime = Environment.DateTime
local Enum = Environment.Enum
local Instance = Environment.Instance
local Vector2 = Environment.Vector2
local Vector3 = Environment.Vector3

local FREE_LENGTH: number = 100 -- As long as an unbounded string, buffer or list gets in a test
local FLOAT_REACH: { [string]: number } = { f16 = 65504, f32 = 2 ^ 20, f64 = 2 ^ 40 } -- How far a random float goes each way
local ROTATION_DRIFT: { [string]: number } = { f16 = math.pi / 1024, f32 = 1e-6, f64 = 1e-12 } -- Per float rotation component
local ALIGNED_DRIFT: number = 1e-5 -- What an aligned rotation may drift by and still be the same one
local TIME_REACH: number = 2 ^ 40 -- The latest timestamp a test sends
local PALETTE: number = 127 -- The last index BrickColor.palette takes
local QUARTER: number = math.pi / 2 -- One aligned turn
local CREATABLE: { [string]: string } = { BasePart = "Part" } -- A class Instance.new accepts for an abstract one
local ITEM_ENUMS: { any } = { Enum.Material, Enum.KeyCode } -- Where an untyped enum item comes from
local COMPONENT: Type = { kind = "primitive", name = Wire.component, start = 0, finish = 0 } -- A vector's default numeric type

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
	local bytes: { string } = table.create(count)
	for index: number = 1, count do
		bytes[index] = string.char(math.random(0, 255))
	end
	return table.concat(bytes)
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

local function unitVector(): any
	return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
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
		local text: string = randomBytes(lengthOf(shape.range, ends))
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
    A value of a Roblox type built from its components at an end or at
    random: an identity rotation at the least, a half turn at the most
--]]

local function robloxOf(shape: any, ends: string?): any
	local name: string = shape.name
	local generics: { Type } = shape.generics or {}
	local component: Type = generics[1] or COMPONENT

	if name == "Vector3" then
		return Vector3.new(valueOf(component, ends), valueOf(component, ends), valueOf(component, ends))
	elseif name == "Vector2" then
		return Vector2.new(valueOf(component, ends), valueOf(component, ends))
	elseif name == "CFrame" then
		local position = Vector3.new(valueOf(component, ends), valueOf(component, ends), valueOf(component, ends))
		local rotation = ends == "min" and CFrame.new()
			or ends == "max" and CFrame.fromAxisAngle(Vector3.yAxis, math.pi)
			or CFrame.fromAxisAngle(unitVector(), math.random() * math.pi)

		return rotation + position
	elseif name == "AlignedCFrame" then
		local position = Vector3.new(valueOf(component, ends), valueOf(component, ends), valueOf(component, ends))
		local turns: number = ends == "min" and 0 or ends == "max" and 3 or math.random(0, 3)

		return CFrame.Angles(turns * QUARTER, math.random(0, 3) * QUARTER, math.random(0, 3) * QUARTER) + position
	elseif name == "Color3" then
		local function channel(): number
			return ends == "min" and 0 or ends == "max" and Wire.channelMax or math.random(0, Wire.channelMax)
		end

		return Color3.fromRGB(channel(), channel(), channel())
	elseif name == "BrickColor" then
		return BrickColor.palette(ends == "min" and 1 or ends == "max" and PALETTE or math.random(1, PALETTE))
	elseif name == "DateTime" or name == "DateTimeMillis" then
		local stamp: number = ends == "min" and 0
			or ends == "max" and TIME_REACH
			or math.floor(math.random() * TIME_REACH)
		return name == "DateTime" and DateTime.fromUnixTimestamp(stamp) or DateTime.fromUnixTimestampMillis(stamp)
	elseif name == "Instance" or name == "StreamedInstance" then
		local class: string = shape.class or "Folder"
		return Instance.new(CREATABLE[class] or class)
	elseif name == "Enum" then
		return pick(Enum[shape.item]:GetEnumItems(), ends)
	end

	return pick(pick(ITEM_ENUMS, ends):GetEnumItems(), ends)
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
	elseif kind == "roblox" then
		return robloxOf(shape, ends)
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

-- How far a rotation component drifts through its numeric type, in radians
local function rotationDrift(node: Type): number
	local shape: any = Sizes.resolved(node)
	local name: string = shape.name
	local levels: number? = Primitives[name].levels
	local low: number, high: number = bounds(shape)

	return ROTATION_DRIFT[name] or levels and (high - low) / levels or 2 * math.pi / (high - low)
end

--[[
    Whether a Roblox value read back matches the one written: component
    by component through the numeric type each carries, and a rotation
    within what its components can drift
--]]

local function robloxNear(shape: any, expected: any, actual: any): boolean
	local name: string = shape.name
	local generics: { Type } = shape.generics or {}
	local component: Type = generics[1] or COMPONENT

	if name == "Vector3" then
		return near(component, expected.X, actual.X)
			and near(component, expected.Y, actual.Y)
			and near(component, expected.Z, actual.Z)
	elseif name == "Vector2" then
		return near(component, expected.X, actual.X) and near(component, expected.Y, actual.Y)
	elseif name == "CFrame" or name == "AlignedCFrame" then
		local drift: number = name == "CFrame" and 2 * rotationDrift(generics[2] or COMPONENT) or ALIGNED_DRIFT

		return near(component, expected.X, actual.X)
			and near(component, expected.Y, actual.Y)
			and near(component, expected.Z, actual.Z)
			and expected.Rotation:FuzzyEq(actual.Rotation, drift + ALIGNED_DRIFT)
	elseif name == "BrickColor" then
		return expected.Number == actual.Number
	elseif name == "DateTime" then
		return expected.UnixTimestamp == actual.UnixTimestamp
	elseif name == "DateTimeMillis" then
		return expected.UnixTimestampMillis == actual.UnixTimestampMillis
	end

	return expected == actual
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
		return robloxNear(shape, expected, actual)
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

return Values
