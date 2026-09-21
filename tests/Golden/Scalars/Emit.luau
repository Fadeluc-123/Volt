local beginReliable, allocateReliable, refuseReliable = ...

local function writeFlags(a: boolean, b: number, c: boolean, d: boolean)
	local offset: number, out: buffer = beginReliable(2)
	local flags: number = 0

	if typeof(a) ~= "boolean" then
		refuseReliable("Flags.a: expected boolean")
	end

	flags += a and 1 or 0

	if typeof(b) ~= "number" or b % 1 ~= 0 or b < 0 or b > 255 then
		refuseReliable("Flags.b: expected u8")
	end

	buffer.writeu8(out, offset + 1, b)

	if typeof(c) ~= "boolean" then
		refuseReliable("Flags.c: expected boolean")
	end

	flags += c and 2 or 0

	if typeof(d) ~= "boolean" then
		refuseReliable("Flags.d: expected boolean")
	end

	flags += d and 4 or 0
	buffer.writeu8(out, offset, flags)
end

local function readFlags(packet: buffer, cursor: number, _, sideCursor: number, length: number)
	if cursor + 2 > length then
		error("Flags: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local b: number = buffer.readu8(packet, cursor + 1)
	cursor += 2

	return cursor, sideCursor, bit32.btest(flags, 1), b, bit32.btest(flags, 2), bit32.btest(flags, 4)
end

local function writeBytes(name: string, tag: string, raw: buffer, fixed: buffer, free: string, health: number)
	local offset: number, out: buffer = beginReliable(12)

	if typeof(name) ~= "string" then
		refuseReliable("Bytes.name: expected string")
	end

	if #name < 1 or #name > 32 then
		refuseReliable("Bytes.name: length out of range")
	end

	buffer.writeu8(out, offset, #name - 1)

	if typeof(tag) ~= "string" then
		refuseReliable("Bytes.tag: expected string")
	end

	if #tag ~= 4 then
		refuseReliable("Bytes.tag: expected 4 bytes")
	end

	buffer.writestring(out, offset + 1, tag)

	if typeof(raw) ~= "buffer" then
		refuseReliable("Bytes.raw: expected buffer")
	end

	if buffer.len(raw) > 1024 then
		refuseReliable("Bytes.raw: length out of range")
	end

	buffer.writeu16(out, offset + 5, buffer.len(raw))

	if typeof(fixed) ~= "buffer" then
		refuseReliable("Bytes.fixed: expected buffer")
	end

	if buffer.len(fixed) ~= 2 then
		refuseReliable("Bytes.fixed: expected 2 bytes")
	end

	buffer.copy(out, offset + 7, fixed)

	if typeof(free) ~= "string" then
		refuseReliable("Bytes.free: expected string")
	end

	if #free > 65535 then
		refuseReliable("Bytes.free: length out of range")
	end

	buffer.writeu16(out, offset + 9, #free)

	if typeof(health) ~= "number" or health % 1 ~= 0 or health < 0 or health > 100 then
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

local function readBytes(packet: buffer, cursor: number, _, sideCursor: number, length: number)
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

	if typeof(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 65535 then
		refuseReliable("Value: expected u16")
	end

	buffer.writeu16(out, offset, value)
end

local function readValue(packet: buffer, cursor: number, _, sideCursor: number, length: number)
	if cursor + 2 > length then
		error("Value: truncated")
	end

	local value: number = buffer.readu16(packet, cursor)
	cursor += 2

	return cursor, sideCursor, value
end

local function writeEmpty()
end

local function readEmpty(_, cursor: number, _, sideCursor: number, _)
	return cursor, sideCursor
end

return {
	Flags = { write = writeFlags, read = readFlags },
	Bytes = { write = writeBytes, read = readBytes },
	Value = { write = writeValue, read = readValue },
	Empty = { write = writeEmpty, read = readEmpty },
}
