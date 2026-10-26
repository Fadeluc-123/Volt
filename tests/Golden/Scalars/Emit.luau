local beginReliable, trimReliable, allocateReliable, refuseReliable = ...

export type Health = number

local function writeFlags(a: boolean, b: number, c: boolean, d: boolean)
	local offset: number, out: buffer = beginReliable(2)
	local flags: number = 0

	if type(a) ~= "boolean" then
		refuseReliable("Flags.a: expected boolean")
	end

	flags += a and 1 or 0

	if type(b) ~= "number" or bit32.band(b, 255) ~= b then
		refuseReliable("Flags.b: expected u8")
	end

	buffer.writeu8(out, offset + 1, b)

	if type(c) ~= "boolean" then
		refuseReliable("Flags.c: expected boolean")
	end

	flags += c and 2 or 0

	if type(d) ~= "boolean" then
		refuseReliable("Flags.d: expected boolean")
	end

	flags += d and 4 or 0
	buffer.writeu8(out, offset, flags)
end

local function readFlags(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 2 > length then
		error("Flags: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local b: number = buffer.readu8(packet, cursor + 1)
	cursor += 2

	return cursor, sideCursor, bit32.btest(flags, 1), b, bit32.btest(flags, 2), bit32.btest(flags, 4)
end

local function writeBytes(name: string, tag: string, raw: buffer, fixed: buffer, free: string, health: Health)
	local offset: number, out: buffer = beginReliable(12)

	if type(name) ~= "string" then
		refuseReliable("Bytes.name: expected string")
	end

	if #name < 1 or #name > 32 then
		refuseReliable("Bytes.name: length out of range")
	end

	buffer.writeu8(out, offset, #name - 1)

	if type(tag) ~= "string" then
		refuseReliable("Bytes.tag: expected string")
	end

	if #tag ~= 4 then
		refuseReliable("Bytes.tag: expected 4 bytes")
	end

	buffer.writestring(out, offset + 1, tag)

	if type(raw) ~= "buffer" then
		refuseReliable("Bytes.raw: expected buffer")
	end

	if buffer.len(raw) > 1024 then
		refuseReliable("Bytes.raw: length out of range")
	end

	buffer.writeu16(out, offset + 5, buffer.len(raw))

	if type(fixed) ~= "buffer" then
		refuseReliable("Bytes.fixed: expected buffer")
	end

	if buffer.len(fixed) ~= 2 then
		refuseReliable("Bytes.fixed: expected 2 bytes")
	end

	buffer.copy(out, offset + 7, fixed)

	if type(free) ~= "string" then
		refuseReliable("Bytes.free: expected string")
	end

	if #free > 65535 then
		refuseReliable("Bytes.free: length out of range")
	end

	buffer.writeu16(out, offset + 9, #free)

	if type(health) ~= "number" or bit32.band(health, 255) ~= health or health > 100 then
		refuseReliable("Bytes.health: expected u8(0..100)")
	end

	buffer.writeu8(out, offset + 11, health)
	local nameOffset: number, nameOut: buffer = allocateReliable(#name)
	buffer.writestring(nameOut, nameOffset, name)
	local rawOffset: number, rawOut: buffer = allocateReliable(buffer.len(raw))
	buffer.copy(rawOut, rawOffset, raw)
	local freeOffset: number, freeOut: buffer = allocateReliable(#free)
	buffer.writestring(freeOut, freeOffset, free)
end

local function readBytes(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 12 > length then
		error("Bytes: truncated")
	end

	local nameLength: number = 1 + buffer.readu8(packet, cursor)

	if nameLength > 32 then
		error("Bytes.name: length out of range")
	end

	local tag: string = buffer.readstring(packet, cursor + 1, 4)
	local rawLength: number = buffer.readu16(packet, cursor + 5)

	if rawLength > 1024 then
		error("Bytes.raw: length out of range")
	end

	local fixed: buffer = buffer.create(2)
	buffer.copy(fixed, 0, packet, cursor + 7, 2)

	local freeLength: number = buffer.readu16(packet, cursor + 9)
	local health: number = buffer.readu8(packet, cursor + 11)

	if health > 100 then
		error("Bytes.health: out of range")
	end

	cursor += 12

	if cursor + nameLength > length then
		error("Bytes.name: truncated")
	end

	local name: string = buffer.readstring(packet, cursor, nameLength)
	cursor += nameLength

	if cursor + rawLength > length then
		error("Bytes.raw: truncated")
	end

	local raw: buffer = buffer.create(rawLength)
	buffer.copy(raw, 0, packet, cursor, rawLength)

	cursor += rawLength

	if cursor + freeLength > length then
		error("Bytes.free: truncated")
	end

	local free: string = buffer.readstring(packet, cursor, freeLength)
	cursor += freeLength

	return cursor, sideCursor, name, tag, raw, fixed, free, health
end

local function writeValue(value: number)
	local offset: number, out: buffer = beginReliable(2)

	if type(value) ~= "number" or bit32.band(value, 65535) ~= value then
		refuseReliable("Value: expected u16")
	end

	buffer.writeu16(out, offset, value)
end

local function readValue(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 2 > length then
		error("Value: truncated")
	end

	local value: number = buffer.readu16(packet, cursor)
	cursor += 2

	return cursor, sideCursor, value
end

local function writeEmpty()
end

local function readEmpty(_: buffer, cursor: number, _: { any }, sideCursor: number, _: number)
	return cursor, sideCursor
end

local function writeBits(value: { boolean })
	local offset: number, out: buffer = beginReliable(3)

	if type(value) ~= "table" then
		refuseReliable("Bits: expected table")
	end

	if #value > 12 then
		refuseReliable("Bits: length out of range")
	end

	buffer.writeu8(out, offset, #value)
	offset += 1

	for byte = 0, (#value + 7) // 8 - 1 do
		local at: number = byte * 8

		local packed: number = (value[at + 1] and 1 or 0)
			+ (value[at + 2] and 2 or 0)
			+ (value[at + 3] and 4 or 0)
			+ (value[at + 4] and 8 or 0)
			+ (value[at + 5] and 16 or 0)
			+ (value[at + 6] and 32 or 0)
			+ (value[at + 7] and 64 or 0)
			+ (value[at + 8] and 128 or 0)

		buffer.writeu8(out, offset + byte, packed)
	end

	offset += (#value + 7) // 8
	trimReliable(offset)
end

local function readBits(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 1 > length then
		error("Bits: truncated")
	end

	local valueLength: number = buffer.readu8(packet, cursor)

	if valueLength > 12 then
		error("Bits: length out of range")
	end

	cursor += 1

	if cursor + (valueLength + 7) // 8 > length then
		error("Bits: truncated")
	end

	local value: { boolean } = table.create(valueLength) :: { boolean }

	for byte = 0, valueLength // 8 - 1 do
		local packed: number = buffer.readu8(packet, cursor + byte)
		local at: number = byte * 8
		value[at + 1] = bit32.btest(packed, 1)
		value[at + 2] = bit32.btest(packed, 2)
		value[at + 3] = bit32.btest(packed, 4)
		value[at + 4] = bit32.btest(packed, 8)
		value[at + 5] = bit32.btest(packed, 16)
		value[at + 6] = bit32.btest(packed, 32)
		value[at + 7] = bit32.btest(packed, 64)
		value[at + 8] = bit32.btest(packed, 128)
	end

	for index = valueLength // 8 * 8 + 1, valueLength do
		value[index] = bit32.btest(buffer.readu8(packet, cursor + (index - 1) // 8), bit32.lshift(1, (index - 1) % 8))
	end

	cursor += (valueLength + 7) // 8

	return cursor, sideCursor, value
end

return {
	Flags = { write = writeFlags, read = readFlags },
	Bytes = { write = writeBytes, read = readBytes },
	Value = { write = writeValue, read = readValue },
	Empty = { write = writeEmpty, read = readEmpty },
	Bits = { write = writeBits, read = readBits },
}
