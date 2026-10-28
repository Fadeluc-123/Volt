local beginReliable, allocateReliable, slotReliable, refuseReliable = ...

export type Stack = { item: string, quantity: number, properties: any? }

local function writeStack(allocate: (number) -> (number, buffer), slot: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(4)
	local flags: number = 0

	if type(value) ~= "table" then
		refuse("Stack: expected table")
	end

	local item = value.item

	if type(item) ~= "string" then
		refuse("Stack.item: expected string")
	end

	if #item < 1 or #item > 8 then
		refuse("Stack.item: length out of range")
	end

	buffer.writeu8(out, offset + 1, #item - 1)
	local quantity = value.quantity

	if type(quantity) ~= "number" or bit32.band(quantity, 65535) ~= quantity or quantity < 1 or quantity > 999 then
		refuse("Stack.quantity: expected u16(1..999)")
	end

	buffer.writeu16(out, offset + 2, quantity)
	local properties = value.properties
	flags += properties ~= nil and 1 or 0

	if properties ~= nil then
		slot(properties)
	end

	buffer.writeu8(out, offset, flags)
	local itemOffset: number, itemOut: buffer = allocate(#item)
	buffer.writestring(itemOut, itemOffset, item)
end

local function readStack(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number, Stack)
	if cursor + 4 > length then
		error("Stack: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local itemLength: number = 1 + buffer.readu8(packet, cursor + 1)

	if itemLength > 8 then
		error("Stack.item: length out of range")
	end

	local quantity: number = buffer.readu16(packet, cursor + 2)

	if quantity < 1 or quantity > 999 then
		error("Stack.quantity: out of range")
	end

	local properties: any = nil

	if bit32.btest(flags, 1) then
		properties = side[sideCursor]
		sideCursor += 1

		if properties == nil then
			error("Stack.properties: missing")
		end
	end

	cursor += 4

	if cursor + itemLength > length then
		error("Stack.item: truncated")
	end

	local item: string = buffer.readstring(packet, cursor, itemLength)
	cursor += itemLength
	local value = { item = item, quantity = quantity, properties = properties }

	return cursor, sideCursor, value
end

local function writeLists(a: { number }, b: { string }, c: { boolean }, d: { boolean }, e: { Stack }, f: { number })
	local offset: number, out: buffer = beginReliable(6)
	local flags: number = 0

	if type(a) ~= "table" then
		refuseReliable("Lists.a: expected table")
	end

	if #a > 8 then
		refuseReliable("Lists.a: length out of range")
	end

	buffer.writeu8(out, offset + 1, #a)

	if type(b) ~= "table" then
		refuseReliable("Lists.b: expected table")
	end

	if #b ~= 2 then
		refuseReliable("Lists.b: expected 2 entries")
	end

	if type(c) ~= "table" then
		refuseReliable("Lists.c: expected table")
	end

	if #c ~= 8 then
		refuseReliable("Lists.c: expected 8 entries")
	end

	flags += (c[1] and 1 or 0)
		+ (c[2] and 2 or 0)
		+ (c[3] and 4 or 0)
		+ (c[4] and 8 or 0)
		+ (c[5] and 16 or 0)
		+ (c[6] and 32 or 0)
		+ (c[7] and 64 or 0)
		+ (c[8] and 128 or 0)

	if type(d) ~= "table" then
		refuseReliable("Lists.d: expected table")
	end

	if #d > 20 then
		refuseReliable("Lists.d: length out of range")
	end

	buffer.writeu8(out, offset + 2, #d)

	if type(e) ~= "table" then
		refuseReliable("Lists.e: expected table")
	end

	if #e > 2 then
		refuseReliable("Lists.e: length out of range")
	end

	buffer.writeu8(out, offset + 3, #e)

	if type(f) ~= "table" then
		refuseReliable("Lists.f: expected table")
	end

	if #f > 65535 then
		refuseReliable("Lists.f: length out of range")
	end

	buffer.writeu16(out, offset + 4, #f)
	buffer.writeu8(out, offset, flags)
	local aOffset: number, aOut: buffer = allocateReliable(#a)

	for index = 1, #a do
		local aEntry = a[index]

		if type(aEntry) ~= "number" or bit32.band(aEntry, 255) ~= aEntry then
			refuseReliable("Lists.a[]: expected u8")
		end

		buffer.writeu8(aOut, aOffset, aEntry)
		aOffset += 1
	end

	for index_2 = 1, 2 do
		local offset_2: number, out_2: buffer = allocateReliable(1)
		local bEntry = b[index_2]

		if type(bEntry) ~= "string" then
			refuseReliable("Lists.b[]: expected string")
		end

		if #bEntry > 4 then
			refuseReliable("Lists.b[]: length out of range")
		end

		buffer.writeu8(out_2, offset_2, #bEntry)
		local bEntryOffset: number, bEntryOut: buffer = allocateReliable(#bEntry)
		buffer.writestring(bEntryOut, bEntryOffset, bEntry)
	end

	local dOffset: number, dOut: buffer = allocateReliable((#d + 7) // 8)

	for byte = 0, (#d + 7) // 8 - 1 do
		local at: number = byte * 8

		local packed: number = (d[at + 1] and 1 or 0)
			+ (d[at + 2] and 2 or 0)
			+ (d[at + 3] and 4 or 0)
			+ (d[at + 4] and 8 or 0)
			+ (d[at + 5] and 16 or 0)
			+ (d[at + 6] and 32 or 0)
			+ (d[at + 7] and 64 or 0)
			+ (d[at + 8] and 128 or 0)

		buffer.writeu8(dOut, dOffset + byte, packed)
	end

	for index_3 = 1, #e do
		writeStack(allocateReliable, slotReliable, refuseReliable, e[index_3])
	end

	local fOffset: number, fOut: buffer = allocateReliable(#f)

	for index_4 = 1, #f do
		local fEntry = f[index_4]

		if type(fEntry) ~= "number" or bit32.band(fEntry, 255) ~= fEntry then
			refuseReliable("Lists.f[]: expected u8")
		end

		buffer.writeu8(fOut, fOffset, fEntry)
		fOffset += 1
	end
end

local function readLists(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	if cursor + 6 > length then
		error("Lists: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local aLength: number = buffer.readu8(packet, cursor + 1)

	if aLength > 8 then
		error("Lists.a: length out of range")
	end

	local c: { boolean } = {
		bit32.btest(flags, 1),
		bit32.btest(flags, 2),
		bit32.btest(flags, 4),
		bit32.btest(flags, 8),
		bit32.btest(flags, 16),
		bit32.btest(flags, 32),
		bit32.btest(flags, 64),
		bit32.btest(flags, 128),
	}

	local dLength: number = buffer.readu8(packet, cursor + 2)

	if dLength > 20 then
		error("Lists.d: length out of range")
	end

	local eLength: number = buffer.readu8(packet, cursor + 3)

	if eLength > 2 then
		error("Lists.e: length out of range")
	end

	local fLength: number = buffer.readu16(packet, cursor + 4)
	cursor += 6

	if cursor + aLength > length then
		error("Lists.a: truncated")
	end

	local a: { number } = table.create(aLength) :: { number }

	for index = 1, aLength do
		local aEntry: number = buffer.readu8(packet, cursor)
		cursor += 1
		a[index] = aEntry
	end

	if cursor + 2 > length then
		error("Lists.b: truncated")
	end

	local b: { string } = table.create(2) :: { string }

	for index_2 = 1, 2 do
		if cursor + 1 > length then
			error("Lists.b: truncated")
		end

		local bEntryLength: number = buffer.readu8(packet, cursor)

		if bEntryLength > 4 then
			error("Lists.b[]: length out of range")
		end

		cursor += 1

		if cursor + bEntryLength > length then
			error("Lists.b[]: truncated")
		end

		local bEntry: string = buffer.readstring(packet, cursor, bEntryLength)
		cursor += bEntryLength
		b[index_2] = bEntry
	end

	if cursor + (dLength + 7) // 8 > length then
		error("Lists.d: truncated")
	end

	local d: { boolean } = table.create(dLength) :: { boolean }

	for byte = 0, dLength // 8 - 1 do
		local packed: number = buffer.readu8(packet, cursor + byte)
		local at: number = byte * 8
		d[at + 1] = bit32.btest(packed, 1)
		d[at + 2] = bit32.btest(packed, 2)
		d[at + 3] = bit32.btest(packed, 4)
		d[at + 4] = bit32.btest(packed, 8)
		d[at + 5] = bit32.btest(packed, 16)
		d[at + 6] = bit32.btest(packed, 32)
		d[at + 7] = bit32.btest(packed, 64)
		d[at + 8] = bit32.btest(packed, 128)
	end

	for index_3 = dLength // 8 * 8 + 1, dLength do
		d[index_3] = bit32.btest(buffer.readu8(packet, cursor + (index_3 - 1) // 8), bit32.lshift(1, (index_3 - 1) % 8))
	end

	cursor += (dLength + 7) // 8

	if cursor + 5 * eLength > length then
		error("Lists.e: truncated")
	end

	local e: { Stack } = table.create(eLength) :: { Stack }

	for index_4 = 1, eLength do
		local eEntry: Stack
		cursor, sideCursor, eEntry = readStack(packet, cursor, side, sideCursor, length)
		e[index_4] = eEntry
	end

	if cursor + fLength > length then
		error("Lists.f: truncated")
	end

	local f: { number } = table.create(fLength) :: { number }

	for index_5 = 1, fLength do
		local fEntry: number = buffer.readu8(packet, cursor)
		cursor += 1
		f[index_5] = fEntry
	end

	return cursor, sideCursor, a, b, c, d, e, f
end

return {
	Lists = { write = writeLists, read = readLists },
}
