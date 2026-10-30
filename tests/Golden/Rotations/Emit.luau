local beginReliable, trimReliable, refuseReliable = ...

local QUATERNION_RANGE: number = math.sqrt(0.5) -- The most a kept component reaches, since none exceeds the largest

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

local function writeTurn(a: CFrame, b: CFrame, c: { { at: CFrame } })
	local offset: number, out: buffer = beginReliable(107)

	if typeof(a) ~= "CFrame" then
		refuseReliable("Turn.a: expected QuaternionCFrame")
	end

	local aRotation: number = packQuaternion(a)

	if aRotation < 0 then
		refuseReliable("Turn.a: expected a rotation")
	end

	buffer.writeu32(out, offset, aRotation)
	local aX = a.X

	if aX ~= aX then
		refuseReliable("Turn.a.X: expected f32")
	end

	buffer.writef32(out, offset + 4, aX)
	local aY = a.Y

	if aY ~= aY then
		refuseReliable("Turn.a.Y: expected f32")
	end

	buffer.writef32(out, offset + 8, aY)
	local aZ = a.Z

	if aZ ~= aZ then
		refuseReliable("Turn.a.Z: expected f32")
	end

	buffer.writef32(out, offset + 12, aZ)

	if typeof(b) ~= "CFrame" then
		refuseReliable("Turn.b: expected QuaternionCFrame<q16(-512..512)>")
	end

	local bRotation: number = packQuaternion(b)

	if bRotation < 0 then
		refuseReliable("Turn.b: expected a rotation")
	end

	buffer.writeu32(out, offset + 16, bRotation)
	local bX = b.X

	if bX ~= bX then
		refuseReliable("Turn.b.X: expected q16(-512..512)")
	end

	buffer.writeu16(out, offset + 20, math.round((math.clamp(bX, -512, 512) + 512) / 1024 * 65535))
	local bY = b.Y

	if bY ~= bY then
		refuseReliable("Turn.b.Y: expected q16(-512..512)")
	end

	buffer.writeu16(out, offset + 22, math.round((math.clamp(bY, -512, 512) + 512) / 1024 * 65535))
	local bZ = b.Z

	if bZ ~= bZ then
		refuseReliable("Turn.b.Z: expected q16(-512..512)")
	end

	buffer.writeu16(out, offset + 24, math.round((math.clamp(bZ, -512, 512) + 512) / 1024 * 65535))

	if type(c) ~= "table" then
		refuseReliable("Turn.c: expected table")
	end

	if #c > 8 then
		refuseReliable("Turn.c: length out of range")
	end

	buffer.writeu8(out, offset + 26, #c)
	offset += 27

	for index = 1, #c do
		local cEntry = c[index]

		if type(cEntry) ~= "table" then
			refuseReliable("Turn.c[]: expected table")
		end

		local at = cEntry.at

		if typeof(at) ~= "CFrame" then
			refuseReliable("Turn.c[].at: expected QuaternionCFrame<i16(-1000..1000)>")
		end

		local atRotation: number = packQuaternion(at)

		if atRotation < 0 then
			refuseReliable("Turn.c[].at: expected a rotation")
		end

		buffer.writeu32(out, offset, atRotation)
		local atX = at.X

		if atX % 1 ~= 0 or atX < -1000 or atX > 1000 then
			refuseReliable("Turn.c[].at.X: expected i16(-1000..1000)")
		end

		buffer.writei16(out, offset + 4, atX)
		local atY = at.Y

		if atY % 1 ~= 0 or atY < -1000 or atY > 1000 then
			refuseReliable("Turn.c[].at.Y: expected i16(-1000..1000)")
		end

		buffer.writei16(out, offset + 6, atY)
		local atZ = at.Z

		if atZ % 1 ~= 0 or atZ < -1000 or atZ > 1000 then
			refuseReliable("Turn.c[].at.Z: expected i16(-1000..1000)")
		end

		buffer.writei16(out, offset + 8, atZ)
		offset += 10
	end

	trimReliable(offset)
end

local function readTurn(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 27 > length then
		error("Turn: truncated")
	end

	local aRotation: CFrame? = unpackQuaternion(buffer.readu32(packet, cursor))

	if not aRotation then
		error("Turn.a: out of range")
	end

	local aX: number = buffer.readf32(packet, cursor + 4)

	if aX ~= aX then
		error("Turn.a.X: out of range")
	end

	local aY: number = buffer.readf32(packet, cursor + 8)

	if aY ~= aY then
		error("Turn.a.Y: out of range")
	end

	local aZ: number = buffer.readf32(packet, cursor + 12)

	if aZ ~= aZ then
		error("Turn.a.Z: out of range")
	end

	local a: CFrame = aRotation + Vector3.new(aX, aY, aZ)
	local bRotation: CFrame? = unpackQuaternion(buffer.readu32(packet, cursor + 16))

	if not bRotation then
		error("Turn.b: out of range")
	end

	local bX: number = -512 + buffer.readu16(packet, cursor + 20) / 65535 * 1024
	local bY: number = -512 + buffer.readu16(packet, cursor + 22) / 65535 * 1024
	local bZ: number = -512 + buffer.readu16(packet, cursor + 24) / 65535 * 1024
	local b: CFrame = bRotation + Vector3.new(bX, bY, bZ)
	local cLength: number = buffer.readu8(packet, cursor + 26)

	if cLength > 8 then
		error("Turn.c: length out of range")
	end

	cursor += 27

	if cursor + 10 * cLength > length then
		error("Turn.c: truncated")
	end

	local c: { { at: CFrame } } = table.create(cLength) :: { { at: CFrame } }

	for index = 1, cLength do
		local atRotation: CFrame? = unpackQuaternion(buffer.readu32(packet, cursor))

		if not atRotation then
			error("Turn.c[].at: out of range")
		end

		local atX: number = buffer.readi16(packet, cursor + 4)

		if atX < -1000 or atX > 1000 then
			error("Turn.c[].at.X: out of range")
		end

		local atY: number = buffer.readi16(packet, cursor + 6)

		if atY < -1000 or atY > 1000 then
			error("Turn.c[].at.Y: out of range")
		end

		local atZ: number = buffer.readi16(packet, cursor + 8)

		if atZ < -1000 or atZ > 1000 then
			error("Turn.c[].at.Z: out of range")
		end

		local at: CFrame = atRotation + Vector3.new(atX, atY, atZ)
		cursor += 10
		local cEntry = { at = at }
		c[index] = cEntry
	end

	return cursor, sideCursor, a, b, c
end

return {
	Turn = { write = writeTurn, read = readTurn },
}
