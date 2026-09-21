--[[
    The helper functions a generated module carries when a type needs
    them, by the name the emitter records: the IEEE half pair, the CFrame
    fold and rebuild, the aligned rotation table and lookup, and the enum
    table an untyped item finds its way back through
--]]

--!strict
local Helpers: { [string]: string } = {
	f16 = [=[
--[[
    Writes a number as an IEEE half: sign, five exponent bits and ten
    fraction bits, rounding to the nearest half and past 65504 to
    infinity
--]]

local function writef16(target: buffer, offset: number, value: number)
	local magnitude: number = math.abs(value)
	local encoded: number = 31744 -- Infinity, which anything past the largest half rounds to

	if magnitude ~= magnitude then
		encoded = 32256
	elseif magnitude < 2 ^ -14 then
		encoded = math.round(magnitude * 2 ^ 24) -- Subnormal, or zero
	elseif magnitude < 65520 then
		local fraction: number, exponent: number = math.frexp(magnitude)
		encoded = math.round((fraction * 2 - 1) * 1024) + (exponent + 14) * 1024
	end

	buffer.writeu16(target, offset, value < 0 and 32768 + encoded or encoded)
end

--[[
    Reads an IEEE half back into a number
--]]

local function readf16(source: buffer, offset: number): number
	local encoded: number = buffer.readu16(source, offset)
	local exponent: number = encoded // 1024 % 32
	local fraction: number = encoded % 1024
	local magnitude: number

	if exponent == 31 then
		magnitude = fraction == 0 and math.huge or 0 / 0
	elseif exponent == 0 then
		magnitude = fraction * 2 ^ -24
	else
		magnitude = (1 + fraction / 1024) * 2 ^ (exponent - 15)
	end

	return encoded >= 32768 and -magnitude or magnitude
end
]=],

	cframe = [=[
--[[
    A CFrame's rotation as an axis and an angle no wider than a half
    turn, since a wider turn is the same rotation the other way about
    the opposite axis
--]]

local function axisAngle(value: CFrame): (Vector3, number)
	local axis: Vector3, angle: number = value:ToAxisAngle()
	if angle > math.pi then
		return -axis, 2 * math.pi - angle
	end
	return axis, angle
end

--[[
    Rebuilds a CFrame from its position and a rotation vector whose
    direction is the axis and whose length is the angle
--]]

local function cframe(x: number, y: number, z: number, rx: number, ry: number, rz: number): CFrame
	local angle: number = math.sqrt(rx * rx + ry * ry + rz * rz)
	if angle == 0 then
		return CFrame.new(x, y, z)
	end
	return CFrame.fromAxisAngle(Vector3.new(rx / angle, ry / angle, rz / angle), angle) + Vector3.new(x, y, z)
end
]=],

	aligned = [=[
-- The 24 rotations whose axes lie along the world axes, in the one order both sides share
local ALIGNED: { CFrame } = {}
local AXES: { Vector3 } = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }
local ALIGNED_TOLERANCE: number = 1e-5 -- How far a rotation may drift from an aligned one and still count

for _, right: Vector3 in AXES do
	for _, up: Vector3 in AXES do
		if right:Dot(up) == 0 then
			table.insert(ALIGNED, CFrame.fromMatrix(Vector3.zero, right, up))
		end
	end
end

--[[
    The index of the aligned rotation a CFrame carries, or nil when its
    rotation is not one of the 24
--]]

local function alignedIndex(value: CFrame): number?
	local rotation: CFrame = value.Rotation
	for index: number, aligned: CFrame in ALIGNED do
		if rotation:FuzzyEq(aligned, ALIGNED_TOLERANCE) then
			return index - 1
		end
	end
	return nil
end
]=],

	enums = [=[
-- Every enum by the name its items report, so an untyped item finds its way back
local ENUMS: { [string]: Enum } = {}
for _, enum: Enum in Enum:GetEnums() do
	ENUMS[tostring(enum)] = enum
end

--[[
    Finds an item of any enum by the enum's name and the item's value, or
    nil when either is unknown
--]]

local function enumItem(name: string, value: number): EnumItem?
	local enum: Enum? = ENUMS[name]
	if not enum then
		return nil
	end

	-- Whiteoak TODO: a scan of the enum's items per read, a table per enum if untyped items show in a profile
	for _, item: EnumItem in enum:GetEnumItems() do
		if item.Value == value then
			return item
		end
	end

	return nil
end
]=],
}

return Helpers
