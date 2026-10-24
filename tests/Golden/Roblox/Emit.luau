local beginReliable, refuseReliable = ...

local function writeVectors(a: Vector3, b: Vector3, c: Vector2, d: Vector3)
	local offset: number, out: buffer = beginReliable(23)

	if typeof(a) ~= "Vector3" then
		refuseReliable("Vectors.a: expected Vector3")
	end

	local aX = a.X

	if aX ~= aX then
		refuseReliable("Vectors.a.X: expected f32")
	end

	buffer.writef32(out, offset, aX)
	local aY = a.Y

	if aY ~= aY then
		refuseReliable("Vectors.a.Y: expected f32")
	end

	buffer.writef32(out, offset + 4, aY)
	local aZ = a.Z

	if aZ ~= aZ then
		refuseReliable("Vectors.a.Z: expected f32")
	end

	buffer.writef32(out, offset + 8, aZ)

	if typeof(b) ~= "Vector3" then
		refuseReliable("Vectors.b: expected Vector3<i16(-1000..1000)>")
	end

	local bX = b.X

	if bX % 1 ~= 0 or bX < -1000 or bX > 1000 then
		refuseReliable("Vectors.b.X: expected i16(-1000..1000)")
	end

	buffer.writei16(out, offset + 12, bX)
	local bY = b.Y

	if bY % 1 ~= 0 or bY < -1000 or bY > 1000 then
		refuseReliable("Vectors.b.Y: expected i16(-1000..1000)")
	end

	buffer.writei16(out, offset + 14, bY)
	local bZ = b.Z

	if bZ % 1 ~= 0 or bZ < -1000 or bZ > 1000 then
		refuseReliable("Vectors.b.Z: expected i16(-1000..1000)")
	end

	buffer.writei16(out, offset + 16, bZ)

	if typeof(c) ~= "Vector2" then
		refuseReliable("Vectors.c: expected Vector2<q8(0..1)>")
	end

	local cX = c.X

	if cX ~= cX then
		refuseReliable("Vectors.c.X: expected q8(0..1)")
	end

	buffer.writeu8(out, offset + 18, math.round(math.clamp(cX, 0, 1) * 255))
	local cY = c.Y

	if cY ~= cY then
		refuseReliable("Vectors.c.Y: expected q8(0..1)")
	end

	buffer.writeu8(out, offset + 19, math.round(math.clamp(cY, 0, 1) * 255))

	if typeof(d) ~= "Vector3" then
		refuseReliable("Vectors.d: expected Vector3<u8>")
	end

	local dX = d.X

	if bit32.band(dX, 255) ~= dX then
		refuseReliable("Vectors.d.X: expected u8")
	end

	buffer.writeu8(out, offset + 20, dX)
	local dY = d.Y

	if bit32.band(dY, 255) ~= dY then
		refuseReliable("Vectors.d.Y: expected u8")
	end

	buffer.writeu8(out, offset + 21, dY)
	local dZ = d.Z

	if bit32.band(dZ, 255) ~= dZ then
		refuseReliable("Vectors.d.Z: expected u8")
	end

	buffer.writeu8(out, offset + 22, dZ)
end

local function readVectors(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 23 > length then
		error("Vectors: truncated")
	end

	local aX: number = buffer.readf32(packet, cursor)

	if aX ~= aX then
		error("Vectors.a.X: out of range")
	end

	local aY: number = buffer.readf32(packet, cursor + 4)

	if aY ~= aY then
		error("Vectors.a.Y: out of range")
	end

	local aZ: number = buffer.readf32(packet, cursor + 8)

	if aZ ~= aZ then
		error("Vectors.a.Z: out of range")
	end

	local a: Vector3 = Vector3.new(aX, aY, aZ)
	local bX: number = buffer.readi16(packet, cursor + 12)

	if bX < -1000 or bX > 1000 then
		error("Vectors.b.X: out of range")
	end

	local bY: number = buffer.readi16(packet, cursor + 14)

	if bY < -1000 or bY > 1000 then
		error("Vectors.b.Y: out of range")
	end

	local bZ: number = buffer.readi16(packet, cursor + 16)

	if bZ < -1000 or bZ > 1000 then
		error("Vectors.b.Z: out of range")
	end

	local b: Vector3 = Vector3.new(bX, bY, bZ)
	local cX: number = buffer.readu8(packet, cursor + 18) / 255
	local cY: number = buffer.readu8(packet, cursor + 19) / 255
	local c: Vector2 = Vector2.new(cX, cY)
	local dX: number = buffer.readu8(packet, cursor + 20)
	local dY: number = buffer.readu8(packet, cursor + 21)
	local dZ: number = buffer.readu8(packet, cursor + 22)
	local d: Vector3 = Vector3.new(dX, dY, dZ)
	cursor += 23

	return cursor, sideCursor, a, b, c, d
end

local function writeColours(a: Color3, b: BrickColor, c: DateTime, d: DateTime)
	local offset: number, out: buffer = beginReliable(21)

	if typeof(a) ~= "Color3" then
		refuseReliable("Colours.a: expected Color3")
	end

	buffer.writeu8(out, offset, math.round(a.R * 255))
	buffer.writeu8(out, offset + 1, math.round(a.G * 255))
	buffer.writeu8(out, offset + 2, math.round(a.B * 255))

	if typeof(b) ~= "BrickColor" then
		refuseReliable("Colours.b: expected BrickColor")
	end

	buffer.writeu16(out, offset + 3, b.Number)

	if typeof(c) ~= "DateTime" then
		refuseReliable("Colours.c: expected DateTime")
	end

	if c.UnixTimestamp ~= c.UnixTimestamp then
		refuseReliable("Colours.c.UnixTimestamp: expected f64")
	end

	buffer.writef64(out, offset + 5, c.UnixTimestamp)

	if typeof(d) ~= "DateTime" then
		refuseReliable("Colours.d: expected DateTimeMillis")
	end

	if d.UnixTimestampMillis ~= d.UnixTimestampMillis then
		refuseReliable("Colours.d.UnixTimestampMillis: expected f64")
	end

	buffer.writef64(out, offset + 13, d.UnixTimestampMillis)
end

local function readColours(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 21 > length then
		error("Colours: truncated")
	end

	local a: Color3 = Color3.fromRGB(buffer.readu8(packet, cursor), buffer.readu8(packet, cursor + 1), buffer.readu8(packet, cursor + 2))
	local bNumber: number = buffer.readu16(packet, cursor + 3)
	local b: BrickColor = BrickColor.new(bNumber)

	if b.Number ~= bNumber then
		error("Colours.b: out of range")
	end

	local cStamp: number = buffer.readf64(packet, cursor + 5)

	if cStamp ~= cStamp then
		error("Colours.c.UnixTimestamp: out of range")
	end

	local c: DateTime = DateTime.fromUnixTimestamp(cStamp)
	local dStamp: number = buffer.readf64(packet, cursor + 13)

	if dStamp ~= dStamp then
		error("Colours.d.UnixTimestampMillis: out of range")
	end

	local d: DateTime = DateTime.fromUnixTimestampMillis(dStamp)
	cursor += 21

	return cursor, sideCursor, a, b, c, d
end

return {
	Vectors = { write = writeVectors, read = readVectors },
	Colours = { write = writeColours, read = readColours },
}
