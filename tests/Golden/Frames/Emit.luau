local beginReliable, refuseReliable = ...

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

local function writeFrames(a: CFrame, b: CFrame, c: CFrame, d: CFrame)
	local offset: number, out: buffer = beginReliable(58)

	if typeof(a) ~= "CFrame" then
		refuseReliable("Frames.a: expected CFrame")
	end

	if a.X ~= a.X then
		refuseReliable("Frames.a.X: expected f32")
	end

	buffer.writef32(out, offset, a.X)

	if a.Y ~= a.Y then
		refuseReliable("Frames.a.Y: expected f32")
	end

	buffer.writef32(out, offset + 4, a.Y)

	if a.Z ~= a.Z then
		refuseReliable("Frames.a.Z: expected f32")
	end

	buffer.writef32(out, offset + 8, a.Z)
	local aAxis: Vector3, aAngle: number = axisAngle(a)

	if aAxis.X * aAngle ~= aAxis.X * aAngle then
		refuseReliable("Frames.a.Rotation.X: expected f32")
	end

	buffer.writef32(out, offset + 12, aAxis.X * aAngle)

	if aAxis.Y * aAngle ~= aAxis.Y * aAngle then
		refuseReliable("Frames.a.Rotation.Y: expected f32")
	end

	buffer.writef32(out, offset + 16, aAxis.Y * aAngle)

	if aAxis.Z * aAngle ~= aAxis.Z * aAngle then
		refuseReliable("Frames.a.Rotation.Z: expected f32")
	end

	buffer.writef32(out, offset + 20, aAxis.Z * aAngle)

	if typeof(b) ~= "CFrame" then
		refuseReliable("Frames.b: expected CFrame<f32, i16>")
	end

	if b.X ~= b.X then
		refuseReliable("Frames.b.X: expected f32")
	end

	buffer.writef32(out, offset + 24, b.X)

	if b.Y ~= b.Y then
		refuseReliable("Frames.b.Y: expected f32")
	end

	buffer.writef32(out, offset + 28, b.Y)

	if b.Z ~= b.Z then
		refuseReliable("Frames.b.Z: expected f32")
	end

	buffer.writef32(out, offset + 32, b.Z)
	local bAxis: Vector3, bAngle: number = axisAngle(b)
	buffer.writei16(out, offset + 36, math.round(-32768 + (bAxis.X * bAngle + math.pi) / (2 * math.pi) * 65535))
	buffer.writei16(out, offset + 38, math.round(-32768 + (bAxis.Y * bAngle + math.pi) / (2 * math.pi) * 65535))
	buffer.writei16(out, offset + 40, math.round(-32768 + (bAxis.Z * bAngle + math.pi) / (2 * math.pi) * 65535))

	if typeof(c) ~= "CFrame" then
		refuseReliable("Frames.c: expected AlignedCFrame<q16(-512..512)>")
	end

	local cRotation: number? = alignedIndex(c)

	if not cRotation then
		refuseReliable("Frames.c: expected an axis-aligned rotation")
	end

	buffer.writeu8(out, offset + 42, cRotation)

	if c.X ~= c.X then
		refuseReliable("Frames.c.X: expected q16(-512..512)")
	end

	buffer.writeu16(out, offset + 43, math.round((math.clamp(c.X, -512, 512) + 512) / 1024 * 65535))

	if c.Y ~= c.Y then
		refuseReliable("Frames.c.Y: expected q16(-512..512)")
	end

	buffer.writeu16(out, offset + 45, math.round((math.clamp(c.Y, -512, 512) + 512) / 1024 * 65535))

	if c.Z ~= c.Z then
		refuseReliable("Frames.c.Z: expected q16(-512..512)")
	end

	buffer.writeu16(out, offset + 47, math.round((math.clamp(c.Z, -512, 512) + 512) / 1024 * 65535))

	if typeof(d) ~= "CFrame" then
		refuseReliable("Frames.d: expected CFrame<i16(-1000..1000), q8(-3.2..3.2)>")
	end

	if d.X % 1 ~= 0 or d.X < -1000 or d.X > 1000 then
		refuseReliable("Frames.d.X: expected i16(-1000..1000)")
	end

	buffer.writei16(out, offset + 49, d.X)

	if d.Y % 1 ~= 0 or d.Y < -1000 or d.Y > 1000 then
		refuseReliable("Frames.d.Y: expected i16(-1000..1000)")
	end

	buffer.writei16(out, offset + 51, d.Y)

	if d.Z % 1 ~= 0 or d.Z < -1000 or d.Z > 1000 then
		refuseReliable("Frames.d.Z: expected i16(-1000..1000)")
	end

	buffer.writei16(out, offset + 53, d.Z)
	local dAxis: Vector3, dAngle: number = axisAngle(d)

	if dAxis.X * dAngle ~= dAxis.X * dAngle then
		refuseReliable("Frames.d.Rotation.X: expected q8(-3.2..3.2)")
	end

	buffer.writeu8(out, offset + 55, math.round((math.clamp(dAxis.X * dAngle, -3.2, 3.2) + 3.2) / 6.4 * 255))

	if dAxis.Y * dAngle ~= dAxis.Y * dAngle then
		refuseReliable("Frames.d.Rotation.Y: expected q8(-3.2..3.2)")
	end

	buffer.writeu8(out, offset + 56, math.round((math.clamp(dAxis.Y * dAngle, -3.2, 3.2) + 3.2) / 6.4 * 255))

	if dAxis.Z * dAngle ~= dAxis.Z * dAngle then
		refuseReliable("Frames.d.Rotation.Z: expected q8(-3.2..3.2)")
	end

	buffer.writeu8(out, offset + 57, math.round((math.clamp(dAxis.Z * dAngle, -3.2, 3.2) + 3.2) / 6.4 * 255))
end

local function readFrames(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 58 > length then
		error("Frames: truncated")
	end

	local aX: number = buffer.readf32(packet, cursor)

	if aX ~= aX then
		error("Frames.a.X: out of range")
	end

	local aY: number = buffer.readf32(packet, cursor + 4)

	if aY ~= aY then
		error("Frames.a.Y: out of range")
	end

	local aZ: number = buffer.readf32(packet, cursor + 8)

	if aZ ~= aZ then
		error("Frames.a.Z: out of range")
	end

	local aRotationX: number = buffer.readf32(packet, cursor + 12)

	if aRotationX ~= aRotationX then
		error("Frames.a.Rotation.X: out of range")
	end

	local aRotationY: number = buffer.readf32(packet, cursor + 16)

	if aRotationY ~= aRotationY then
		error("Frames.a.Rotation.Y: out of range")
	end

	local aRotationZ: number = buffer.readf32(packet, cursor + 20)

	if aRotationZ ~= aRotationZ then
		error("Frames.a.Rotation.Z: out of range")
	end

	local a: CFrame = cframe(aX, aY, aZ, aRotationX, aRotationY, aRotationZ)
	local bX: number = buffer.readf32(packet, cursor + 24)

	if bX ~= bX then
		error("Frames.b.X: out of range")
	end

	local bY: number = buffer.readf32(packet, cursor + 28)

	if bY ~= bY then
		error("Frames.b.Y: out of range")
	end

	local bZ: number = buffer.readf32(packet, cursor + 32)

	if bZ ~= bZ then
		error("Frames.b.Z: out of range")
	end

	local bRotationX: number = buffer.readi16(packet, cursor + 36)
	local bRotationY: number = buffer.readi16(packet, cursor + 38)
	local bRotationZ: number = buffer.readi16(packet, cursor + 40)
	local b: CFrame = cframe(bX, bY, bZ, (bRotationX + 32768) / 65535 * (2 * math.pi) - math.pi, (bRotationY + 32768) / 65535 * (2 * math.pi) - math.pi, (bRotationZ + 32768) / 65535 * (2 * math.pi) - math.pi)
	local cRotation: CFrame? = ALIGNED[buffer.readu8(packet, cursor + 42) + 1]

	if not cRotation then
		error("Frames.c: out of range")
	end

	local cX: number = -512 + buffer.readu16(packet, cursor + 43) / 65535 * 1024
	local cY: number = -512 + buffer.readu16(packet, cursor + 45) / 65535 * 1024
	local cZ: number = -512 + buffer.readu16(packet, cursor + 47) / 65535 * 1024
	local c: CFrame = cRotation + Vector3.new(cX, cY, cZ)
	local dX: number = buffer.readi16(packet, cursor + 49)

	if dX < -1000 or dX > 1000 then
		error("Frames.d.X: out of range")
	end

	local dY: number = buffer.readi16(packet, cursor + 51)

	if dY < -1000 or dY > 1000 then
		error("Frames.d.Y: out of range")
	end

	local dZ: number = buffer.readi16(packet, cursor + 53)

	if dZ < -1000 or dZ > 1000 then
		error("Frames.d.Z: out of range")
	end

	local dRotationX: number = -3.2 + buffer.readu8(packet, cursor + 55) / 255 * 6.4
	local dRotationY: number = -3.2 + buffer.readu8(packet, cursor + 56) / 255 * 6.4
	local dRotationZ: number = -3.2 + buffer.readu8(packet, cursor + 57) / 255 * 6.4
	local d: CFrame = cframe(dX, dY, dZ, dRotationX, dRotationY, dRotationZ)
	cursor += 58

	return cursor, sideCursor, a, b, c, d
end

return {
	Frames = { write = writeFrames, read = readFrames },
}
