local beginReliable, refuseReliable = ...

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

local function writeIntegers(a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number, j: number, k: number, l: number)
	local offset: number, out: buffer = beginReliable(48)

	if typeof(a) ~= "number" or a % 1 ~= 0 or a < 0 or a > 255 then
		refuseReliable("Integers.a: expected u8")
	end

	buffer.writeu8(out, offset, a)

	if typeof(b) ~= "number" or b % 1 ~= 0 or b < 1 or b > 999 then
		refuseReliable("Integers.b: expected u16(1..999)")
	end

	buffer.writeu16(out, offset + 1, b)

	if typeof(c) ~= "number" or c % 1 ~= 0 or c < 0 or c > 16777215 then
		refuseReliable("Integers.c: expected u24")
	end

	buffer.writeu8(out, offset + 3, c % 256)
	buffer.writeu16(out, offset + 4, c // 256)

	if typeof(d) ~= "number" or d % 1 ~= 0 or d < 0 or d > 4294967295 then
		refuseReliable("Integers.d: expected u32")
	end

	buffer.writeu32(out, offset + 6, d)

	if typeof(e) ~= "number" or e % 1 ~= 0 or e < 0 or e > 281474976710655 then
		refuseReliable("Integers.e: expected u48")
	end

	buffer.writeu16(out, offset + 10, e % 65536)
	buffer.writeu32(out, offset + 12, e // 65536)

	if typeof(f) ~= "number" or f % 1 ~= 0 or f < 0 or f > 9007199254740992 then
		refuseReliable("Integers.f: expected u64")
	end

	buffer.writeu32(out, offset + 16, f % 4294967296)
	buffer.writeu32(out, offset + 20, f // 4294967296)

	if typeof(g) ~= "number" or g % 1 ~= 0 or g < -5 or g > 5 then
		refuseReliable("Integers.g: expected i8(-5..5)")
	end

	buffer.writei8(out, offset + 24, g)

	if typeof(h) ~= "number" or h % 1 ~= 0 or h < -32768 or h > 32767 then
		refuseReliable("Integers.h: expected i16")
	end

	buffer.writei16(out, offset + 25, h)

	if typeof(i) ~= "number" or i % 1 ~= 0 or i < -8388608 or i > 8388607 then
		refuseReliable("Integers.i: expected i24")
	end

	buffer.writeu8(out, offset + 27, i % 256)
	buffer.writeu16(out, offset + 28, 32768 + i // 256)

	if typeof(j) ~= "number" or j % 1 ~= 0 or j < -2147483648 or j > 2147483647 then
		refuseReliable("Integers.j: expected i32")
	end

	buffer.writei32(out, offset + 30, j)

	if typeof(k) ~= "number" or k % 1 ~= 0 or k < -140737488355328 or k > 140737488355327 then
		refuseReliable("Integers.k: expected i48")
	end

	buffer.writeu16(out, offset + 34, k % 65536)
	buffer.writeu32(out, offset + 36, 2147483648 + k // 65536)

	if typeof(l) ~= "number" or l % 1 ~= 0 or l < -9007199254740992 or l > 9007199254740992 then
		refuseReliable("Integers.l: expected i64")
	end

	buffer.writeu32(out, offset + 40, l % 4294967296)
	buffer.writeu32(out, offset + 44, 2147483648 + l // 4294967296)
end

local function readIntegers(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 48 > length then
		error("Integers: truncated")
	end

	local a: number = buffer.readu8(packet, cursor)
	local b: number = buffer.readu16(packet, cursor + 1)

	if b < 1 or b > 999 then
		error("Integers.b: out of range")
	end

	local c: number = buffer.readu8(packet, cursor + 3) + buffer.readu16(packet, cursor + 4) * 256
	local d: number = buffer.readu32(packet, cursor + 6)
	local e: number = buffer.readu16(packet, cursor + 10) + buffer.readu32(packet, cursor + 12) * 65536
	local fLow: number = buffer.readu32(packet, cursor + 16)
	local fHigh: number = buffer.readu32(packet, cursor + 20)

	if fHigh > 2097152 or fHigh == 2097152 and fLow > 0 then
		error("Integers.f: out of range")
	end

	local f: number = fLow + fHigh * 4294967296
	local g: number = buffer.readi8(packet, cursor + 24)

	if g < -5 or g > 5 then
		error("Integers.g: out of range")
	end

	local h: number = buffer.readi16(packet, cursor + 25)
	local i: number = buffer.readu8(packet, cursor + 27) + (buffer.readu16(packet, cursor + 28) - 32768) * 256
	local j: number = buffer.readi32(packet, cursor + 30)
	local k: number = buffer.readu16(packet, cursor + 34) + (buffer.readu32(packet, cursor + 36) - 2147483648) * 65536
	local lLow: number = buffer.readu32(packet, cursor + 40)
	local lHigh: number = buffer.readu32(packet, cursor + 44) - 2147483648

	if math.abs(lHigh) > 2097152 or math.abs(lHigh) == 2097152 and lLow > 0 then
		error("Integers.l: out of range")
	end

	local l: number = lLow + lHigh * 4294967296
	cursor += 48

	return cursor, sideCursor, a, b, c, d, e, f, g, h, i, j, k, l
end

local function writeFloats(a: number, b: number, c: number, d: number, e: number)
	local offset: number, out: buffer = beginReliable(17)

	if typeof(a) ~= "number" or a ~= a then
		refuseReliable("Floats.a: expected f16")
	end

	writef16(out, offset, a)

	if typeof(b) ~= "number" or b ~= b then
		refuseReliable("Floats.b: expected f32")
	end

	buffer.writef32(out, offset + 2, b)

	if typeof(c) ~= "number" or c ~= c or c < 0 or c > 1 then
		refuseReliable("Floats.c: expected f64(0..1)")
	end

	buffer.writef64(out, offset + 6, c)

	if typeof(d) ~= "number" or d ~= d then
		refuseReliable("Floats.d: expected q8(0..1)")
	end

	buffer.writeu8(out, offset + 14, math.round(math.clamp(d, 0, 1) * 255))

	if typeof(e) ~= "number" or e ~= e then
		refuseReliable("Floats.e: expected q16(-3.2..3.2)")
	end

	buffer.writeu16(out, offset + 15, math.round((math.clamp(e, -3.2, 3.2) + 3.2) / 6.4 * 65535))
end

local function readFloats(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 17 > length then
		error("Floats: truncated")
	end

	local a: number = readf16(packet, cursor)

	if a ~= a then
		error("Floats.a: out of range")
	end

	local b: number = buffer.readf32(packet, cursor + 2)

	if b ~= b then
		error("Floats.b: out of range")
	end

	local c: number = buffer.readf64(packet, cursor + 6)

	if c ~= c or c < 0 or c > 1 then
		error("Floats.c: out of range")
	end

	local d: number = buffer.readu8(packet, cursor + 14) / 255
	local e: number = -3.2 + buffer.readu16(packet, cursor + 15) / 65535 * 6.4
	cursor += 17

	return cursor, sideCursor, a, b, c, d, e
end

return {
	Integers = { write = writeIntegers, read = readIntegers },
	Floats = { write = writeFloats, read = readFloats },
}
