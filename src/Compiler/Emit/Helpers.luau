--[[
    The helpers a generated module carries when a type needs them, by the
    name the emitter records: the IEEE half pair, the CFrame fold and
    rebuild, the aligned rotations and their lookup, the smallest-three
    quaternion pair, and the enum table an untyped item finds its way back
    through, each a list of pieces that declare one name apiece, so a
    module keeps only the pieces it calls
--]]

--!strict
local Helpers: { [string]: { string } } = {
	f16 = {
		[=[
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
]=],
		[=[
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
	},

	cframe = {
		[=[
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
]=],
		[=[
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
	},

	aligned = {
		[=[
-- The 24 rotations whose axes lie along the world axes, in the one order both sides share
local ALIGNED: { CFrame } = {}
local AXES: { Vector3 } = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }

for _, right: Vector3 in AXES do
	for _, up: Vector3 in AXES do
		if right:Dot(up) == 0 then
			table.insert(ALIGNED, CFrame.fromMatrix(Vector3.zero, right, up))
		end
	end
end
]=],
		[=[
local ALIGNED_TOLERANCE: number = 1e-5 -- How far a rotation may drift from an aligned one and still count

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
	},

	quaternion = {
		[=[
local QUATERNION_RANGE: number = math.sqrt(0.5) -- The most a kept component reaches, since none exceeds the largest
]=],
		[=[
--[[
    A CFrame's rotation as its smallest three quaternion components in a
    u32: the index of the largest component in the top two bits, then the
    other three in X, Y, Z, W order, ten bits each, negated first when the
    largest is negative. Returns -1 for a rotation with no finite quaternion
--]]

local function packQuaternion(value: CFrame): number
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()
	local trace: number = r00 + r11 + r22
	local x: number, y: number, z: number, w: number

	-- Shepperd's branches, each the quaternion times four times its largest component, so normalizing finishes it
	if trace > 0 then
		x, y, z, w = r21 - r12, r02 - r20, r10 - r01, 1 + trace
	elseif r00 > r11 and r00 > r22 then
		x, y, z, w = 1 + r00 - r11 - r22, r01 + r10, r02 + r20, r21 - r12
	elseif r11 > r22 then
		x, y, z, w = r01 + r10, 1 - r00 + r11 - r22, r12 + r21, r02 - r20
	else
		x, y, z, w = r02 + r20, r12 + r21, 1 - r00 - r11 + r22, r10 - r01
	end

	local length: number = math.sqrt(x * x + y * y + z * z + w * w)

	if not (length > 0 and length < math.huge) then
		return -1
	end

	-- The first largest is dropped, and the kept three move down into x, y and z in order
	local index: number, largest: number = 0, x

	if math.abs(y) > math.abs(largest) then
		index, largest = 1, y
	end
	if math.abs(z) > math.abs(largest) then
		index, largest = 2, z
	end
	if math.abs(w) > math.abs(largest) then
		index, largest = 3, w
	end

	if index == 0 then
		x, y, z = y, z, w
	elseif index == 1 then
		y, z = z, w
	elseif index == 2 then
		z = w
	end

	local scale: number = (largest < 0 and -511 or 511) / (length * QUATERNION_RANGE)
	local a: number = math.clamp(math.round(x * scale), -511, 511) + 512
	local b: number = math.clamp(math.round(y * scale), -511, 511) + 512
	local c: number = math.clamp(math.round(z * scale), -511, 511) + 512

	return index * 2 ^ 30 + a * 2 ^ 20 + b * 2 ^ 10 + c
end
]=],
		[=[
--[[
    The rotation a u32 of smallest three components carries, or nil when
    the three square past one and leave the dropped component no value
--]]

local function unpackQuaternion(packed: number): CFrame?
	local a: number = (bit32.extract(packed, 20, 10) - 512) / 511 * QUATERNION_RANGE
	local b: number = (bit32.extract(packed, 10, 10) - 512) / 511 * QUATERNION_RANGE
	local c: number = (bit32.extract(packed, 0, 10) - 512) / 511 * QUATERNION_RANGE
	local rest: number = 1 - a * a - b * b - c * c

	if rest < 0 then
		return nil
	end

	local dropped: number = math.sqrt(rest)
	local index: number = bit32.extract(packed, 30, 2)

	if index == 0 then
		return CFrame.new(0, 0, 0, dropped, a, b, c)
	elseif index == 1 then
		return CFrame.new(0, 0, 0, a, dropped, b, c)
	elseif index == 2 then
		return CFrame.new(0, 0, 0, a, b, dropped, c)
	end

	return CFrame.new(0, 0, 0, a, b, c, dropped)
end
]=],
	},

	enums = {
		[=[
-- Every enum by the name its items report, so an untyped item finds its way back
local ENUMS: { [string]: Enum } = {}
for _, enum: Enum in Enum:GetEnums() do
	ENUMS[tostring(enum)] = enum
end
]=],
		[=[
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
	},
}

return Helpers
