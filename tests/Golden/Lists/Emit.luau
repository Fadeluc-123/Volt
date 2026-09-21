local allocateReliable, slotReliable = ...

local function writeStack(allocate: (number) -> (number, buffer), slot: (any) -> (), value: any)
	local offset: number, out: buffer = allocate(4)
	local flags: number = 0

	if typeof(value) ~= "table" then
		error("Stack: expected table")
	end

	if typeof(value.item) ~= "string" then
		error("Stack.item: expected string")
	end

	if #value.item < 1 or #value.item > 8 then
		error("Stack.item: length out of range")
	end

	buffer.writeu8(out, offset + 1, #value.item - 1)

	if typeof(value.quantity) ~= "number" or value.quantity % 1 ~= 0 or value.quantity < 1 or value.quantity > 999 then
		error("Stack.quantity: expected u16(1..999)")
	end

	buffer.writeu16(out, offset + 2, value.quantity)
	flags += value.properties ~= nil and 1 or 0

	if value.properties ~= nil then
		slot(value.properties)
	end

	buffer.writeu8(out, offset, flags)
	local itemOffset: number, itemOut: buffer = allocate(#value.item)
	buffer.writestring(itemOut, itemOffset, value.item)
end

local function readStack(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
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

local function writeLists(a: any, b: any, c: any, d: any, e: any, f: any)
	local offset: number, out: buffer = allocateReliable(6)
	local flags: number = 0

	if typeof(a) ~= "table" then
		error("Lists.a: expected table")
	end

	if #a > 8 then
		error("Lists.a: length out of range")
	end

	buffer.writeu8(out, offset + 1, #a)

	if typeof(b) ~= "table" then
		error("Lists.b: expected table")
	end

	if #b ~= 2 then
		error("Lists.b: expected 2 entries")
	end

	if typeof(c) ~= "table" then
		error("Lists.c: expected table")
	end

	if #c ~= 8 then
		error("Lists.c: expected 8 entries")
	end

	for index_3 = 1, 8 do
		flags += c[index_3] and 2 ^ (index_3 - 1) or 0
	end

	if typeof(d) ~= "table" then
		error("Lists.d: expected table")
	end

	if #d > 20 then
		error("Lists.d: length out of range")
	end

	buffer.writeu8(out, offset + 2, #d)

	if typeof(e) ~= "table" then
		error("Lists.e: expected table")
	end

	if #e > 2 then
		error("Lists.e: length out of range")
	end

	buffer.writeu8(out, offset + 3, #e)

	if typeof(f) ~= "table" then
		error("Lists.f: expected table")
	end

	if #f > 65535 then
		error("Lists.f: length out of range")
	end

	buffer.writeu16(out, offset + 4, #f)
	buffer.writeu8(out, offset, flags)
	local aOffset: number, aOut: buffer = allocateReliable(#a)

	for index = 1, #a do
		if typeof(a[index]) ~= "number" or a[index] % 1 ~= 0 or a[index] < 0 or a[index] > 255 then
			error("Lists.a[]: expected u8")
		end

		buffer.writeu8(aOut, aOffset, a[index])
		aOffset += 1
	end

	for index_2 = 1, 2 do
		local offset_2: number, out_2: buffer = allocateReliable(1)

		if typeof(b[index_2]) ~= "string" then
			error("Lists.b[]: expected string")
		end

		if #b[index_2] > 4 then
			error("Lists.b[]: length out of range")
		end

		buffer.writeu8(out_2, offset_2, #b[index_2])
		local bEntryOffset: number, bEntryOut: buffer = allocateReliable(#b[index_2])
		buffer.writestring(bEntryOut, bEntryOffset, b[index_2])
	end

	local dOffset: number, dOut: buffer = allocateReliable((#d + 7) // 8)

	for byte = 0, (#d + 7) // 8 - 1 do
		local packed: number = 0

		for bit = 0, 7 do
			packed += d[byte * 8 + bit + 1] and 2 ^ bit or 0
		end

		buffer.writeu8(dOut, dOffset + byte, packed)
	end

	for index_5 = 1, #e do
		writeStack(allocateReliable, slotReliable, e[index_5])
	end

	local fOffset: number, fOut: buffer = allocateReliable(#f)

	for index_6 = 1, #f do
		if typeof(f[index_6]) ~= "number" or f[index_6] % 1 ~= 0 or f[index_6] < 0 or f[index_6] > 255 then
			error("Lists.f[]: expected u8")
		end

		buffer.writeu8(fOut, fOffset, f[index_6])
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

	local c: { boolean } = table.create(8)

	for index_3 = 1, 8 do
		c[index_3] = bit32.btest(flags, 2 ^ (index_3 - 1))
	end

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

	local a = table.create(aLength)

	for index = 1, aLength do
		local aEntry: number = buffer.readu8(packet, cursor)
		cursor += 1
		a[index] = aEntry
	end

	if cursor + 2 > length then
		error("Lists.b: truncated")
	end

	local b = table.create(2)

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

	local d: { boolean } = table.create(dLength)

	for index_4 = 1, dLength do
		d[index_4] = bit32.btest(buffer.readu8(packet, cursor + (index_4 - 1) // 8), 2 ^ ((index_4 - 1) % 8))
	end

	cursor += (dLength + 7) // 8

	if cursor + 5 * eLength > length then
		error("Lists.e: truncated")
	end

	local e = table.create(eLength)

	for index_5 = 1, eLength do
		local eEntry
		cursor, sideCursor, eEntry = readStack(packet, cursor, side, sideCursor, length)
		e[index_5] = eEntry
	end

	if cursor + fLength > length then
		error("Lists.f: truncated")
	end

	local f = table.create(fLength)

	for index_6 = 1, fLength do
		local fEntry: number = buffer.readu8(packet, cursor)
		cursor += 1
		f[index_6] = fEntry
	end

	return cursor, sideCursor, a, b, c, d, e, f
end

return {
	Lists = { write = writeLists, read = readLists },
}
