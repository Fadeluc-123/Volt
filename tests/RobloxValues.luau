--[[
    Values of the Roblox types for the round-trip tests, built from their
    components at an end or at random, and the comparison that says whether
    one read back matches the one written: component by component through
    the numeric type each carries, a rotation and a region within their drift
--]]

--!strict
local Environment = require("./Environment")
local Primitives = require("@volt/Compiler/Config/Primitives")
local Roblox = require("@volt/Compiler/Config/Roblox")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Wire = require("@volt/Compiler/Config/Wire")

type Type = Schema.Type

-- What these take from the values of every type: a value and a comparison of any type, a number's bounds and a pick
export type Values = {
	valueOf: (Type, string?) -> any,
	near: (Type, any, any) -> boolean,
	bounds: (any) -> (number, number),
	pick: ({ any }, string?) -> any,
}

local BrickColor = Environment.BrickColor
local CFrame = Environment.CFrame
local Color3 = Environment.Color3
local DateTime = Environment.DateTime
local Enum = Environment.Enum
local Instance = Environment.Instance
local Ray = Environment.Ray
local Region3 = Environment.Region3
local Vector3 = Environment.Vector3

local ROTATION_DRIFT: { [string]: number } = { f16 = math.pi / 1024, f32 = 1e-6, f64 = 1e-12 } -- Per float rotation component
local ALIGNED_DRIFT: number = 1e-5 -- What an aligned rotation may drift by and still be the same one
local QUATERNION_DRIFT: number = 0.005 -- What a smallest-three rotation may drift by, in radians
local ROUNDING: { [string]: number } = { f16 = 2 ^ -10, f32 = 2 ^ -23 } -- How far a float rounds, for its magnitude
local STORED: number = 2 ^ -23 -- How far the f32s a Region3 keeps its centre and size in round, for their magnitude
local TIME_REACH: number = 2 ^ 40 -- The latest timestamp a test sends
local PALETTE: number = 127 -- The last index BrickColor.palette takes
local QUARTER: number = math.pi / 2 -- One aligned turn
local CREATABLE: { [string]: string } = { BasePart = "Part" } -- A class Instance.new accepts for an abstract one
local ITEM_ENUMS: { any } = { Enum.Material, Enum.KeyCode } -- Where an untyped enum item comes from
local COMPONENT: Type = { kind = "primitive", name = Wire.component, start = 0, finish = 0 } -- A component's default type
local AXES: { string } = Roblox.Vector3.axes :: { string }

local RobloxValues = {}

local function unitVector(): any
	return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
end

-- A Vector3 of three numbers of a type, at an end or at random
local function vectorOf(values: Values, component: Type, ends: string?): any
	local x: number, y: number, z: number =
		values.valueOf(component, ends), values.valueOf(component, ends), values.valueOf(component, ends)

	return Vector3.new(x, y, z)
end

-- What a dotted property path names in a value, such as a UDim2's X.Scale
local function at(value: any, path: string): any
	for key: string in path:gmatch("[^.]+") do
		value = value[key]
	end
	return value
end

--[[
    A value of a Roblox type built from its components at an end or at
    random: a range's two in order, an identity rotation at the least and a
    half turn at the most
--]]

function RobloxValues.valueOf(shape: any, ends: string?, values: Values): any
	local name: string = shape.name
	local row = Roblox[name]
	local generics: { Type } = shape.generics or {}
	local component: Type = generics[1] or COMPONENT

	if row.axes then
		local arguments: { number } = row.arguments or {}
		local parts: { number } = {}

		for index: number in row.axes do
			parts[index] = values.valueOf(generics[arguments[index] or 1] or COMPONENT, ends)
		end

		-- A range's reader refuses its ends reversed, so no writer sends them so
		if name == "NumberRange" then
			table.sort(parts)
		end

		return Environment[name].new(table.unpack(parts))
	elseif name == "Ray" then
		return Ray.new(vectorOf(values, component, ends), vectorOf(values, generics[2] or COMPONENT, ends))
	elseif name == "Region3" then
		return Region3.new(vectorOf(values, component, ends), vectorOf(values, component, ends))
	elseif name == "CFrame" or name == "QuaternionCFrame" then
		local position = vectorOf(values, component, ends)
		local rotation = ends == "min" and CFrame.new()
			or ends == "max" and CFrame.fromAxisAngle(Vector3.yAxis, math.pi)
			or CFrame.fromAxisAngle(unitVector(), math.random() * math.pi)

		return rotation + position
	elseif name == "AlignedCFrame" then
		local position = vectorOf(values, component, ends)
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
		return values.pick(Enum[shape.item]:GetEnumItems(), ends)
	end

	return values.pick(values.pick(ITEM_ENUMS, ends):GetEnumItems(), ends)
end

-- How far a rotation component drifts through its numeric type, in radians
local function rotationDrift(values: Values, node: any): number
	local name: string = node.name
	local levels: number? = Primitives[name].levels
	local low: number, high: number = values.bounds(node)

	return ROTATION_DRIFT[name] or levels and (high - low) / levels or 2 * math.pi / (high - low)
end

local function vectorNear(values: Values, component: Type, expected: any, actual: any): boolean
	for _, axis: string in AXES do
		if not values.near(component, expected[axis], actual[axis]) then
			return false
		end
	end
	return true
end

--[[
    Whether a Region3 read back has the centre and size written along
    every axis: within twice what its corners' type, a step or a float's
    rounding, and the f32s it is kept in can each move a number as large
    as its corners by
--]]

local function regionNear(values: Values, component: any, expected: any, actual: any): boolean
	local levels: number? = Primitives[component.name].levels
	local low: number, high: number = values.bounds(component)

	for _, axis: string in AXES do
		local centre: number, size: number = expected.CFrame.Position[axis], expected.Size[axis]
		local magnitude: number = math.abs(centre) + math.abs(size) / 2
		local step: number = levels and (high - low) / levels / 2 or (ROUNDING[component.name] or 0) * magnitude
		local drift: number = 2 * (step + magnitude * STORED)

		if math.abs(actual.CFrame.Position[axis] - centre) > drift or math.abs(actual.Size[axis] - size) > drift then
			return false
		end
	end

	return true
end

--[[
    Whether a Roblox value read back matches the one written: component
    by component through the numeric type each carries, and a rotation or
    a region within what its components can drift
--]]

function RobloxValues.near(shape: any, expected: any, actual: any, values: Values): boolean
	local name: string = shape.name
	local row = Roblox[name]
	local generics: { Type } = shape.generics or {}
	local component: Type = generics[1] or COMPONENT

	if row.axes then
		local arguments: { number } = row.arguments or {}

		for index: number, axis: string in row.axes do
			local argument: Type = generics[arguments[index] or 1] or COMPONENT
			if not values.near(argument, at(expected, axis), at(actual, axis)) then
				return false
			end
		end

		return true
	elseif name == "Ray" then
		local direction: Type = generics[2] or COMPONENT

		return vectorNear(values, component, expected.Origin, actual.Origin)
			and vectorNear(values, direction, expected.Direction, actual.Direction)
	elseif name == "Region3" then
		return regionNear(values, component, expected, actual)
	elseif name == "CFrame" or name == "AlignedCFrame" or name == "QuaternionCFrame" then
		local drift: number = name == "CFrame" and 2 * rotationDrift(values, generics[2] or COMPONENT)
			or name == "QuaternionCFrame" and QUATERNION_DRIFT
			or ALIGNED_DRIFT

		return vectorNear(values, component, expected.Position, actual.Position)
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

return RobloxValues
