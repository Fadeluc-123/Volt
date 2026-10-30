local beginReliable, refuseReliable = ...

local function writeLayouts(a: UDim2, b: UDim2, c: NumberRange, d: NumberRange, e: Rect, f: Rect)
	local offset: number, out: buffer = beginReliable(58)

	if typeof(a) ~= "UDim2" then
		refuseReliable("Layouts.a: expected UDim2")
	end

	local aXScale = a.X.Scale

	if aXScale ~= aXScale then
		refuseReliable("Layouts.a.X.Scale: expected f32")
	end

	buffer.writef32(out, offset, aXScale)
	local aXOffset = a.X.Offset

	if aXOffset ~= aXOffset then
		refuseReliable("Layouts.a.X.Offset: expected f32")
	end

	buffer.writef32(out, offset + 4, aXOffset)
	local aYScale = a.Y.Scale

	if aYScale ~= aYScale then
		refuseReliable("Layouts.a.Y.Scale: expected f32")
	end

	buffer.writef32(out, offset + 8, aYScale)
	local aYOffset = a.Y.Offset

	if aYOffset ~= aYOffset then
		refuseReliable("Layouts.a.Y.Offset: expected f32")
	end

	buffer.writef32(out, offset + 12, aYOffset)

	if typeof(b) ~= "UDim2" then
		refuseReliable("Layouts.b: expected UDim2<q16(0..1), i16>")
	end

	local bXScale = b.X.Scale

	if bXScale ~= bXScale then
		refuseReliable("Layouts.b.X.Scale: expected q16(0..1)")
	end

	buffer.writeu16(out, offset + 16, math.round(math.clamp(bXScale, 0, 1) * 65535))
	local bXOffset = b.X.Offset

	if bXOffset % 1 ~= 0 or bXOffset < -32768 or bXOffset > 32767 then
		refuseReliable("Layouts.b.X.Offset: expected i16")
	end

	buffer.writei16(out, offset + 18, bXOffset)
	local bYScale = b.Y.Scale

	if bYScale ~= bYScale then
		refuseReliable("Layouts.b.Y.Scale: expected q16(0..1)")
	end

	buffer.writeu16(out, offset + 20, math.round(math.clamp(bYScale, 0, 1) * 65535))
	local bYOffset = b.Y.Offset

	if bYOffset % 1 ~= 0 or bYOffset < -32768 or bYOffset > 32767 then
		refuseReliable("Layouts.b.Y.Offset: expected i16")
	end

	buffer.writei16(out, offset + 22, bYOffset)

	if typeof(c) ~= "NumberRange" then
		refuseReliable("Layouts.c: expected NumberRange")
	end

	local cMin = c.Min

	if cMin ~= cMin then
		refuseReliable("Layouts.c.Min: expected f32")
	end

	buffer.writef32(out, offset + 24, cMin)
	local cMax = c.Max

	if cMax ~= cMax then
		refuseReliable("Layouts.c.Max: expected f32")
	end

	buffer.writef32(out, offset + 28, cMax)

	if typeof(d) ~= "NumberRange" then
		refuseReliable("Layouts.d: expected NumberRange<u8(0..100)>")
	end

	local dMin = d.Min

	if bit32.band(dMin, 255) ~= dMin or dMin > 100 then
		refuseReliable("Layouts.d.Min: expected u8(0..100)")
	end

	buffer.writeu8(out, offset + 32, dMin)
	local dMax = d.Max

	if bit32.band(dMax, 255) ~= dMax or dMax > 100 then
		refuseReliable("Layouts.d.Max: expected u8(0..100)")
	end

	buffer.writeu8(out, offset + 33, dMax)

	if typeof(e) ~= "Rect" then
		refuseReliable("Layouts.e: expected Rect")
	end

	local eMinX = e.Min.X

	if eMinX ~= eMinX then
		refuseReliable("Layouts.e.Min.X: expected f32")
	end

	buffer.writef32(out, offset + 34, eMinX)
	local eMinY = e.Min.Y

	if eMinY ~= eMinY then
		refuseReliable("Layouts.e.Min.Y: expected f32")
	end

	buffer.writef32(out, offset + 38, eMinY)
	local eMaxX = e.Max.X

	if eMaxX ~= eMaxX then
		refuseReliable("Layouts.e.Max.X: expected f32")
	end

	buffer.writef32(out, offset + 42, eMaxX)
	local eMaxY = e.Max.Y

	if eMaxY ~= eMaxY then
		refuseReliable("Layouts.e.Max.Y: expected f32")
	end

	buffer.writef32(out, offset + 46, eMaxY)

	if math.abs(eMinX) == math.huge or math.abs(eMinY) == math.huge or math.abs(eMaxX) == math.huge or math.abs(eMaxY) == math.huge then
		refuseReliable("Layouts.e: expected Rect")
	end

	if typeof(f) ~= "Rect" then
		refuseReliable("Layouts.f: expected Rect<q16(0..1)>")
	end

	local fMinX = f.Min.X

	if fMinX ~= fMinX then
		refuseReliable("Layouts.f.Min.X: expected q16(0..1)")
	end

	buffer.writeu16(out, offset + 50, math.round(math.clamp(fMinX, 0, 1) * 65535))
	local fMinY = f.Min.Y

	if fMinY ~= fMinY then
		refuseReliable("Layouts.f.Min.Y: expected q16(0..1)")
	end

	buffer.writeu16(out, offset + 52, math.round(math.clamp(fMinY, 0, 1) * 65535))
	local fMaxX = f.Max.X

	if fMaxX ~= fMaxX then
		refuseReliable("Layouts.f.Max.X: expected q16(0..1)")
	end

	buffer.writeu16(out, offset + 54, math.round(math.clamp(fMaxX, 0, 1) * 65535))
	local fMaxY = f.Max.Y

	if fMaxY ~= fMaxY then
		refuseReliable("Layouts.f.Max.Y: expected q16(0..1)")
	end

	buffer.writeu16(out, offset + 56, math.round(math.clamp(fMaxY, 0, 1) * 65535))
end

local function readLayouts(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 58 > length then
		error("Layouts: truncated")
	end

	local aXScale: number = buffer.readf32(packet, cursor)

	if aXScale ~= aXScale then
		error("Layouts.a.X.Scale: out of range")
	end

	local aXOffset: number = buffer.readf32(packet, cursor + 4)

	if aXOffset ~= aXOffset then
		error("Layouts.a.X.Offset: out of range")
	end

	local aYScale: number = buffer.readf32(packet, cursor + 8)

	if aYScale ~= aYScale then
		error("Layouts.a.Y.Scale: out of range")
	end

	local aYOffset: number = buffer.readf32(packet, cursor + 12)

	if aYOffset ~= aYOffset then
		error("Layouts.a.Y.Offset: out of range")
	end

	local a: UDim2 = UDim2.new(aXScale, aXOffset, aYScale, aYOffset)
	local bXScale: number = buffer.readu16(packet, cursor + 16) / 65535
	local bXOffset: number = buffer.readi16(packet, cursor + 18)
	local bYScale: number = buffer.readu16(packet, cursor + 20) / 65535
	local bYOffset: number = buffer.readi16(packet, cursor + 22)
	local b: UDim2 = UDim2.new(bXScale, bXOffset, bYScale, bYOffset)
	local cMin: number = buffer.readf32(packet, cursor + 24)

	if cMin ~= cMin then
		error("Layouts.c.Min: out of range")
	end

	local cMax: number = buffer.readf32(packet, cursor + 28)

	if cMax ~= cMax then
		error("Layouts.c.Max: out of range")
	end

	if cMin > cMax then
		error("Layouts.c: out of range")
	end

	local c: NumberRange = NumberRange.new(cMin, cMax)
	local dMin: number = buffer.readu8(packet, cursor + 32)

	if dMin > 100 then
		error("Layouts.d.Min: out of range")
	end

	local dMax: number = buffer.readu8(packet, cursor + 33)

	if dMax > 100 then
		error("Layouts.d.Max: out of range")
	end

	if dMin > dMax then
		error("Layouts.d: out of range")
	end

	local d: NumberRange = NumberRange.new(dMin, dMax)
	local eMinX: number = buffer.readf32(packet, cursor + 34)

	if eMinX ~= eMinX then
		error("Layouts.e.Min.X: out of range")
	end

	local eMinY: number = buffer.readf32(packet, cursor + 38)

	if eMinY ~= eMinY then
		error("Layouts.e.Min.Y: out of range")
	end

	local eMaxX: number = buffer.readf32(packet, cursor + 42)

	if eMaxX ~= eMaxX then
		error("Layouts.e.Max.X: out of range")
	end

	local eMaxY: number = buffer.readf32(packet, cursor + 46)

	if eMaxY ~= eMaxY then
		error("Layouts.e.Max.Y: out of range")
	end

	if math.abs(eMinX) == math.huge or math.abs(eMinY) == math.huge or math.abs(eMaxX) == math.huge or math.abs(eMaxY) == math.huge then
		error("Layouts.e: out of range")
	end

	local e: Rect = Rect.new(eMinX, eMinY, eMaxX, eMaxY)
	local fMinX: number = buffer.readu16(packet, cursor + 50) / 65535
	local fMinY: number = buffer.readu16(packet, cursor + 52) / 65535
	local fMaxX: number = buffer.readu16(packet, cursor + 54) / 65535
	local fMaxY: number = buffer.readu16(packet, cursor + 56) / 65535
	local f: Rect = Rect.new(fMinX, fMinY, fMaxX, fMaxY)
	cursor += 58

	return cursor, sideCursor, a, b, c, d, e, f
end

return {
	Layouts = { write = writeLayouts, read = readLayouts },
}
