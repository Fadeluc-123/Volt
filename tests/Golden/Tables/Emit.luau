local allocateReliable, slotReliable = ...

local TEAM: { string } = { "Red", "Blue" }

local function writeTeam(allocate: (number) -> (number, buffer), _, value: any)
	local offset: number, out: buffer = allocate(1)
	local flags: number = 0
	local valueIndex: number? = table.find(TEAM, value)

	if not valueIndex then
		error("Team: expected enum { Red, Blue }")
	end

	flags += valueIndex - 1
	buffer.writeu8(out, offset, flags)
end

local function readTeam(packet: buffer, cursor: number, _, sideCursor: number, length: number)
	if cursor + 1 > length then
		error("Team: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local value: string? = TEAM[bit32.extract(flags, 0, 1) + 1]

	if not value then
		error("Team: out of range")
	end

	cursor += 1

	return cursor, sideCursor, value
end

local function writeTables(a: any, b: any, c: any, d: any)
	local offset: number, out: buffer = allocateReliable(3)

	if typeof(a) ~= "table" then
		error("Tables.a: expected table")
	end

	local aCount: number = 0

	for _ in a do
		aCount += 1
	end

	if aCount > 8 then
		error("Tables.a: length out of range")
	end

	buffer.writeu8(out, offset, aCount)

	if typeof(b) ~= "table" then
		error("Tables.b: expected table")
	end

	local bCount: number = 0

	for _ in b do
		bCount += 1
	end

	if bCount > 8 then
		error("Tables.b: length out of range")
	end

	buffer.writeu8(out, offset + 1, bCount)

	if typeof(c) ~= "table" then
		error("Tables.c: expected table")
	end

	local cCount: number = 0

	for _ in c do
		cCount += 1
	end

	if cCount > 2 then
		error("Tables.c: length out of range")
	end

	buffer.writeu8(out, offset + 2, cCount)

	if typeof(d) ~= "table" then
		error("Tables.d: expected table")
	end

	local dCount: number = 0

	for _ in d do
		dCount += 1
	end

	if dCount ~= 3 then
		error("Tables.d: expected 3 entries")
	end

	for aKey, aValue in a do
		local offset_2: number, out_2: buffer = allocateReliable(2)

		if typeof(aKey) ~= "number" or aKey % 1 ~= 0 or aKey < 0 or aKey > 255 then
			error("Tables.a[key]: expected u8")
		end

		buffer.writeu8(out_2, offset_2, aKey)

		if typeof(aValue) ~= "string" then
			error("Tables.a[value]: expected string")
		end

		if #aValue > 4 then
			error("Tables.a[value]: length out of range")
		end

		buffer.writeu8(out_2, offset_2 + 1, #aValue)
		local aValueOffset: number, aValueOut: buffer = allocateReliable(#aValue)
		buffer.writestring(aValueOut, aValueOffset, aValue)
	end

	for bKey in b do
		local offset_3: number, out_3: buffer = allocateReliable(1)

		if typeof(bKey) ~= "string" then
			error("Tables.b[]: expected string")
		end

		if #bKey < 1 or #bKey > 4 then
			error("Tables.b[]: length out of range")
		end

		buffer.writeu8(out_3, offset_3, #bKey - 1)
		local bKeyOffset: number, bKeyOut: buffer = allocateReliable(#bKey)
		buffer.writestring(bKeyOut, bKeyOffset, bKey)
	end

	for cKey, cValue in c do
		local offset_4: number, out_4: buffer = allocateReliable(2)

		if typeof(cValue) ~= "number" or cValue % 1 ~= 0 or cValue < 0 or cValue > 65535 then
			error("Tables.c[value]: expected u16")
		end

		buffer.writeu16(out_4, offset_4, cValue)
		writeTeam(allocateReliable, slotReliable, cKey)
	end

	local dOffset: number, dOut: buffer = allocateReliable(3)

	for dKey in d do
		if typeof(dKey) ~= "number" or dKey % 1 ~= 0 or dKey < 0 or dKey > 255 then
			error("Tables.d[]: expected u8")
		end

		buffer.writeu8(dOut, dOffset, dKey)
		dOffset += 1
	end
end

local function readTables(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	if cursor + 3 > length then
		error("Tables: truncated")
	end

	local aLength: number = buffer.readu8(packet, cursor)

	if aLength > 8 then
		error("Tables.a: length out of range")
	end

	local bLength: number = buffer.readu8(packet, cursor + 1)

	if bLength > 8 then
		error("Tables.b: length out of range")
	end

	local cLength: number = buffer.readu8(packet, cursor + 2)

	if cLength > 2 then
		error("Tables.c: length out of range")
	end

	cursor += 3

	if cursor + 2 * aLength > length then
		error("Tables.a: truncated")
	end

	local a = {}

	for _ = 1, aLength do
		if cursor + 2 > length then
			error("Tables.a: truncated")
		end

		local aKey: number = buffer.readu8(packet, cursor)
		local aValueLength: number = buffer.readu8(packet, cursor + 1)

		if aValueLength > 4 then
			error("Tables.a[value]: length out of range")
		end

		cursor += 2

		if cursor + aValueLength > length then
			error("Tables.a[value]: truncated")
		end

		local aValue: string = buffer.readstring(packet, cursor, aValueLength)
		cursor += aValueLength

		if a[aKey] ~= nil then
			error("Tables.a: duplicate key")
		end

		a[aKey] = aValue
	end

	if cursor + 2 * bLength > length then
		error("Tables.b: truncated")
	end

	local b = {}

	for _ = 1, bLength do
		if cursor + 1 > length then
			error("Tables.b: truncated")
		end

		local bKeyLength: number = 1 + buffer.readu8(packet, cursor)

		if bKeyLength > 4 then
			error("Tables.b[]: length out of range")
		end

		cursor += 1

		if cursor + bKeyLength > length then
			error("Tables.b[]: truncated")
		end

		local bKey: string = buffer.readstring(packet, cursor, bKeyLength)
		cursor += bKeyLength

		if b[bKey] ~= nil then
			error("Tables.b: duplicate key")
		end

		b[bKey] = true
	end

	if cursor + 3 * cLength > length then
		error("Tables.c: truncated")
	end

	local c = {}

	for _ = 1, cLength do
		if cursor + 2 > length then
			error("Tables.c: truncated")
		end

		local cKey
		local cValue: number = buffer.readu16(packet, cursor)
		cursor += 2
		cursor, sideCursor, cKey = readTeam(packet, cursor, side, sideCursor, length)

		if c[cKey] ~= nil then
			error("Tables.c: duplicate key")
		end

		c[cKey] = cValue
	end

	if cursor + 3 > length then
		error("Tables.d: truncated")
	end

	local d = {}

	for _ = 1, 3 do
		local dKey: number = buffer.readu8(packet, cursor)
		cursor += 1

		if d[dKey] ~= nil then
			error("Tables.d: duplicate key")
		end

		d[dKey] = true
	end

	return cursor, sideCursor, a, b, c, d
end

return {
	Tables = { write = writeTables, read = readTables },
}
