local beginReliable, refuseReliable = ...

local function writeVolumes(a: Ray, b: Ray, c: Region3, d: Region3)
	local offset: number, out: buffer = beginReliable(72)

	if typeof(a) ~= "Ray" then
		refuseReliable("Volumes.a: expected Ray")
	end

	local aOrigin = a.Origin
	local aOriginX = aOrigin.X

	if aOriginX ~= aOriginX then
		refuseReliable("Volumes.a.Origin.X: expected f32")
	end

	buffer.writef32(out, offset, aOriginX)
	local aOriginY = aOrigin.Y

	if aOriginY ~= aOriginY then
		refuseReliable("Volumes.a.Origin.Y: expected f32")
	end

	buffer.writef32(out, offset + 4, aOriginY)
	local aOriginZ = aOrigin.Z

	if aOriginZ ~= aOriginZ then
		refuseReliable("Volumes.a.Origin.Z: expected f32")
	end

	buffer.writef32(out, offset + 8, aOriginZ)
	local aDirection = a.Direction
	local aDirectionX = aDirection.X

	if aDirectionX ~= aDirectionX then
		refuseReliable("Volumes.a.Direction.X: expected f32")
	end

	buffer.writef32(out, offset + 12, aDirectionX)
	local aDirectionY = aDirection.Y

	if aDirectionY ~= aDirectionY then
		refuseReliable("Volumes.a.Direction.Y: expected f32")
	end

	buffer.writef32(out, offset + 16, aDirectionY)
	local aDirectionZ = aDirection.Z

	if aDirectionZ ~= aDirectionZ then
		refuseReliable("Volumes.a.Direction.Z: expected f32")
	end

	buffer.writef32(out, offset + 20, aDirectionZ)

	if typeof(b) ~= "Ray" then
		refuseReliable("Volumes.b: expected Ray<i16(-2048..2048), q16(-512..512)>")
	end

	local bOrigin = b.Origin
	local bOriginX = bOrigin.X

	if bOriginX % 1 ~= 0 or bOriginX < -2048 or bOriginX > 2048 then
		refuseReliable("Volumes.b.Origin.X: expected i16(-2048..2048)")
	end

	buffer.writei16(out, offset + 24, bOriginX)
	local bOriginY = bOrigin.Y

	if bOriginY % 1 ~= 0 or bOriginY < -2048 or bOriginY > 2048 then
		refuseReliable("Volumes.b.Origin.Y: expected i16(-2048..2048)")
	end

	buffer.writei16(out, offset + 26, bOriginY)
	local bOriginZ = bOrigin.Z

	if bOriginZ % 1 ~= 0 or bOriginZ < -2048 or bOriginZ > 2048 then
		refuseReliable("Volumes.b.Origin.Z: expected i16(-2048..2048)")
	end

	buffer.writei16(out, offset + 28, bOriginZ)
	local bDirection = b.Direction
	local bDirectionX = bDirection.X

	if bDirectionX ~= bDirectionX then
		refuseReliable("Volumes.b.Direction.X: expected q16(-512..512)")
	end

	buffer.writeu16(out, offset + 30, math.round((math.clamp(bDirectionX, -512, 512) + 512) / 1024 * 65535))
	local bDirectionY = bDirection.Y

	if bDirectionY ~= bDirectionY then
		refuseReliable("Volumes.b.Direction.Y: expected q16(-512..512)")
	end

	buffer.writeu16(out, offset + 32, math.round((math.clamp(bDirectionY, -512, 512) + 512) / 1024 * 65535))
	local bDirectionZ = bDirection.Z

	if bDirectionZ ~= bDirectionZ then
		refuseReliable("Volumes.b.Direction.Z: expected q16(-512..512)")
	end

	buffer.writeu16(out, offset + 34, math.round((math.clamp(bDirectionZ, -512, 512) + 512) / 1024 * 65535))

	if typeof(c) ~= "Region3" then
		refuseReliable("Volumes.c: expected Region3")
	end

	local cMin = c.CFrame.Position - c.Size / 2
	local cMax = c.CFrame.Position + c.Size / 2

	if math.abs(cMin.X) == math.huge or math.abs(cMin.Y) == math.huge or math.abs(cMin.Z) == math.huge or math.abs(cMax.X) == math.huge or math.abs(cMax.Y) == math.huge or math.abs(cMax.Z) == math.huge then
		refuseReliable("Volumes.c: expected Region3")
	end

	local cMinX = cMin.X

	if cMinX ~= cMinX then
		refuseReliable("Volumes.c.Min.X: expected f32")
	end

	buffer.writef32(out, offset + 36, cMinX)
	local cMinY = cMin.Y

	if cMinY ~= cMinY then
		refuseReliable("Volumes.c.Min.Y: expected f32")
	end

	buffer.writef32(out, offset + 40, cMinY)
	local cMinZ = cMin.Z

	if cMinZ ~= cMinZ then
		refuseReliable("Volumes.c.Min.Z: expected f32")
	end

	buffer.writef32(out, offset + 44, cMinZ)
	local cMaxX = cMax.X

	if cMaxX ~= cMaxX then
		refuseReliable("Volumes.c.Max.X: expected f32")
	end

	buffer.writef32(out, offset + 48, cMaxX)
	local cMaxY = cMax.Y

	if cMaxY ~= cMaxY then
		refuseReliable("Volumes.c.Max.Y: expected f32")
	end

	buffer.writef32(out, offset + 52, cMaxY)
	local cMaxZ = cMax.Z

	if cMaxZ ~= cMaxZ then
		refuseReliable("Volumes.c.Max.Z: expected f32")
	end

	buffer.writef32(out, offset + 56, cMaxZ)

	if typeof(d) ~= "Region3" then
		refuseReliable("Volumes.d: expected Region3<q16(-4096..4096)>")
	end

	local dMin = d.CFrame.Position - d.Size / 2
	local dMax = d.CFrame.Position + d.Size / 2
	local dMinX = dMin.X

	if dMinX ~= dMinX then
		refuseReliable("Volumes.d.Min.X: expected q16(-4096..4096)")
	end

	buffer.writeu16(out, offset + 60, math.round((math.clamp(dMinX, -4096, 4096) + 4096) / 8192 * 65535))
	local dMinY = dMin.Y

	if dMinY ~= dMinY then
		refuseReliable("Volumes.d.Min.Y: expected q16(-4096..4096)")
	end

	buffer.writeu16(out, offset + 62, math.round((math.clamp(dMinY, -4096, 4096) + 4096) / 8192 * 65535))
	local dMinZ = dMin.Z

	if dMinZ ~= dMinZ then
		refuseReliable("Volumes.d.Min.Z: expected q16(-4096..4096)")
	end

	buffer.writeu16(out, offset + 64, math.round((math.clamp(dMinZ, -4096, 4096) + 4096) / 8192 * 65535))
	local dMaxX = dMax.X

	if dMaxX ~= dMaxX then
		refuseReliable("Volumes.d.Max.X: expected q16(-4096..4096)")
	end

	buffer.writeu16(out, offset + 66, math.round((math.clamp(dMaxX, -4096, 4096) + 4096) / 8192 * 65535))
	local dMaxY = dMax.Y

	if dMaxY ~= dMaxY then
		refuseReliable("Volumes.d.Max.Y: expected q16(-4096..4096)")
	end

	buffer.writeu16(out, offset + 68, math.round((math.clamp(dMaxY, -4096, 4096) + 4096) / 8192 * 65535))
	local dMaxZ = dMax.Z

	if dMaxZ ~= dMaxZ then
		refuseReliable("Volumes.d.Max.Z: expected q16(-4096..4096)")
	end

	buffer.writeu16(out, offset + 70, math.round((math.clamp(dMaxZ, -4096, 4096) + 4096) / 8192 * 65535))
end

local function readVolumes(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 72 > length then
		error("Volumes: truncated")
	end

	local aOriginX: number = buffer.readf32(packet, cursor)

	if aOriginX ~= aOriginX then
		error("Volumes.a.Origin.X: out of range")
	end

	local aOriginY: number = buffer.readf32(packet, cursor + 4)

	if aOriginY ~= aOriginY then
		error("Volumes.a.Origin.Y: out of range")
	end

	local aOriginZ: number = buffer.readf32(packet, cursor + 8)

	if aOriginZ ~= aOriginZ then
		error("Volumes.a.Origin.Z: out of range")
	end

	local aOrigin: Vector3 = Vector3.new(aOriginX, aOriginY, aOriginZ)
	local aDirectionX: number = buffer.readf32(packet, cursor + 12)

	if aDirectionX ~= aDirectionX then
		error("Volumes.a.Direction.X: out of range")
	end

	local aDirectionY: number = buffer.readf32(packet, cursor + 16)

	if aDirectionY ~= aDirectionY then
		error("Volumes.a.Direction.Y: out of range")
	end

	local aDirectionZ: number = buffer.readf32(packet, cursor + 20)

	if aDirectionZ ~= aDirectionZ then
		error("Volumes.a.Direction.Z: out of range")
	end

	local aDirection: Vector3 = Vector3.new(aDirectionX, aDirectionY, aDirectionZ)
	local a: Ray = Ray.new(aOrigin, aDirection)
	local bOriginX: number = buffer.readi16(packet, cursor + 24)

	if bOriginX < -2048 or bOriginX > 2048 then
		error("Volumes.b.Origin.X: out of range")
	end

	local bOriginY: number = buffer.readi16(packet, cursor + 26)

	if bOriginY < -2048 or bOriginY > 2048 then
		error("Volumes.b.Origin.Y: out of range")
	end

	local bOriginZ: number = buffer.readi16(packet, cursor + 28)

	if bOriginZ < -2048 or bOriginZ > 2048 then
		error("Volumes.b.Origin.Z: out of range")
	end

	local bOrigin: Vector3 = Vector3.new(bOriginX, bOriginY, bOriginZ)
	local bDirectionX: number = -512 + buffer.readu16(packet, cursor + 30) / 65535 * 1024
	local bDirectionY: number = -512 + buffer.readu16(packet, cursor + 32) / 65535 * 1024
	local bDirectionZ: number = -512 + buffer.readu16(packet, cursor + 34) / 65535 * 1024
	local bDirection: Vector3 = Vector3.new(bDirectionX, bDirectionY, bDirectionZ)
	local b: Ray = Ray.new(bOrigin, bDirection)
	local cMinX: number = buffer.readf32(packet, cursor + 36)

	if cMinX ~= cMinX then
		error("Volumes.c.Min.X: out of range")
	end

	local cMinY: number = buffer.readf32(packet, cursor + 40)

	if cMinY ~= cMinY then
		error("Volumes.c.Min.Y: out of range")
	end

	local cMinZ: number = buffer.readf32(packet, cursor + 44)

	if cMinZ ~= cMinZ then
		error("Volumes.c.Min.Z: out of range")
	end

	local cMin: Vector3 = Vector3.new(cMinX, cMinY, cMinZ)
	local cMaxX: number = buffer.readf32(packet, cursor + 48)

	if cMaxX ~= cMaxX then
		error("Volumes.c.Max.X: out of range")
	end

	local cMaxY: number = buffer.readf32(packet, cursor + 52)

	if cMaxY ~= cMaxY then
		error("Volumes.c.Max.Y: out of range")
	end

	local cMaxZ: number = buffer.readf32(packet, cursor + 56)

	if cMaxZ ~= cMaxZ then
		error("Volumes.c.Max.Z: out of range")
	end

	local cMax: Vector3 = Vector3.new(cMaxX, cMaxY, cMaxZ)

	if math.abs(cMin.X) == math.huge or math.abs(cMin.Y) == math.huge or math.abs(cMin.Z) == math.huge or math.abs(cMax.X) == math.huge or math.abs(cMax.Y) == math.huge or math.abs(cMax.Z) == math.huge then
		error("Volumes.c: out of range")
	end

	local c: Region3 = Region3.new(cMin, cMax)
	local dMinX: number = -4096 + buffer.readu16(packet, cursor + 60) / 65535 * 8192
	local dMinY: number = -4096 + buffer.readu16(packet, cursor + 62) / 65535 * 8192
	local dMinZ: number = -4096 + buffer.readu16(packet, cursor + 64) / 65535 * 8192
	local dMin: Vector3 = Vector3.new(dMinX, dMinY, dMinZ)
	local dMaxX: number = -4096 + buffer.readu16(packet, cursor + 66) / 65535 * 8192
	local dMaxY: number = -4096 + buffer.readu16(packet, cursor + 68) / 65535 * 8192
	local dMaxZ: number = -4096 + buffer.readu16(packet, cursor + 70) / 65535 * 8192
	local dMax: Vector3 = Vector3.new(dMaxX, dMaxY, dMaxZ)
	local d: Region3 = Region3.new(dMin, dMax)
	cursor += 72

	return cursor, sideCursor, a, b, c, d
end

return {
	Volumes = { write = writeVolumes, read = readVolumes },
}
