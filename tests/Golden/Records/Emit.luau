local beginReliable, trimReliable, allocateReliable, slotReliable, refuseReliable = ...

export type Stack = { item: string, quantity: number, properties: any? }
export type Save = { version: number, stacks: { Stack } }

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

local function writeSave(allocate: (number) -> (number, buffer), slot: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(3)

	if type(value) ~= "table" then
		refuse("Save: expected table")
	end

	local version = value.version

	if type(version) ~= "number" or bit32.band(version, 65535) ~= version then
		refuse("Save.version: expected u16")
	end

	buffer.writeu16(out, offset, version)
	local stacks = value.stacks

	if type(stacks) ~= "table" then
		refuse("Save.stacks: expected table")
	end

	if #stacks > 4 then
		refuse("Save.stacks: length out of range")
	end

	buffer.writeu8(out, offset + 2, #stacks)

	for index = 1, #stacks do
		writeStack(allocate, slot, refuse, stacks[index])
	end
end

local function readSave(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number, Save)
	if cursor + 3 > length then
		error("Save: truncated")
	end

	local version: number = buffer.readu16(packet, cursor)
	local stacksLength: number = buffer.readu8(packet, cursor + 2)

	if stacksLength > 4 then
		error("Save.stacks: length out of range")
	end

	cursor += 3

	if cursor + 5 * stacksLength > length then
		error("Save.stacks: truncated")
	end

	local stacks: { Stack } = table.create(stacksLength) :: { Stack }

	for index = 1, stacksLength do
		local stacksEntry: Stack
		cursor, sideCursor, stacksEntry = readStack(packet, cursor, side, sideCursor, length)
		stacks[index] = stacksEntry
	end

	local value = { version = version, stacks = stacks }

	return cursor, sideCursor, value
end

local function writeRecords(a: { x: number, y: string, z: boolean }, b: {}, c: Stack, d: Save)
	local offset: number, out: buffer = beginReliable(3)
	local flags: number = 0

	if type(a) ~= "table" then
		refuseReliable("Records.a: expected table")
	end

	local x = a.x

	if type(x) ~= "number" or bit32.band(x, 255) ~= x then
		refuseReliable("Records.a.x: expected u8")
	end

	buffer.writeu8(out, offset + 1, x)
	local y = a.y

	if type(y) ~= "string" then
		refuseReliable("Records.a.y: expected string")
	end

	if #y > 4 then
		refuseReliable("Records.a.y: length out of range")
	end

	buffer.writeu8(out, offset + 2, #y)
	local z = a.z

	if type(z) ~= "boolean" then
		refuseReliable("Records.a.z: expected boolean")
	end

	flags += z and 1 or 0

	if type(b) ~= "table" then
		refuseReliable("Records.b: expected table")
	end

	buffer.writeu8(out, offset, flags)
	local yOffset: number, yOut: buffer = allocateReliable(#y)
	buffer.writestring(yOut, yOffset, y)
	writeStack(allocateReliable, slotReliable, refuseReliable, c)
	writeSave(allocateReliable, slotReliable, refuseReliable, d)
end

local function readRecords(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	if cursor + 3 > length then
		error("Records: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local x: number = buffer.readu8(packet, cursor + 1)
	local yLength: number = buffer.readu8(packet, cursor + 2)

	if yLength > 4 then
		error("Records.a.y: length out of range")
	end

	local c: Stack
	local d: Save
	cursor += 3

	if cursor + yLength > length then
		error("Records.a.y: truncated")
	end

	local y: string = buffer.readstring(packet, cursor, yLength)
	cursor += yLength
	local a = { x = x, y = y, z = bit32.btest(flags, 1) }
	local b = {}
	cursor, sideCursor, c = readStack(packet, cursor, side, sideCursor, length)
	cursor, sideCursor, d = readSave(packet, cursor, side, sideCursor, length)

	return cursor, sideCursor, a, b, c, d
end

local function writeRows(a: { { id: number, name: string, tag: number? } }, b: { number })
	local offset: number, out: buffer = beginReliable(33)

	if type(a) ~= "table" then
		refuseReliable("Rows.a: expected table")
	end

	if #a > 3 then
		refuseReliable("Rows.a: length out of range")
	end

	buffer.writeu8(out, offset, #a)

	if type(b) ~= "table" then
		refuseReliable("Rows.b: expected table")
	end

	if #b > 4 then
		refuseReliable("Rows.b: length out of range")
	end

	buffer.writeu8(out, offset + 1, #b)
	offset += 2

	for index = 1, #a do
		local flags: number = 0
		local aEntry = a[index]

		if type(aEntry) ~= "table" then
			refuseReliable("Rows.a[]: expected table")
		end

		local id = aEntry.id

		if type(id) ~= "number" or bit32.band(id, 255) ~= id then
			refuseReliable("Rows.a[].id: expected u8")
		end

		buffer.writeu8(out, offset + 1, id)
		local name = aEntry.name

		if type(name) ~= "string" then
			refuseReliable("Rows.a[].name: expected string")
		end

		if #name > 4 then
			refuseReliable("Rows.a[].name: length out of range")
		end

		buffer.writeu8(out, offset + 2, #name)
		local tag = aEntry.tag
		flags += tag ~= nil and 1 or 0
		buffer.writeu8(out, offset, flags)
		offset += 3
		buffer.writestring(out, offset, name)
		offset += #name

		if tag ~= nil then
			if type(tag) ~= "number" or bit32.band(tag, 65535) ~= tag then
				refuseReliable("Rows.a[].tag: expected u16")
			end

			buffer.writeu16(out, offset, tag)
			offset += 2
		end
	end

	for index_2 = 1, #b do
		local bEntry = b[index_2]

		if type(bEntry) ~= "number" or bit32.band(bEntry, 255) ~= bEntry then
			refuseReliable("Rows.b[]: expected u8")
		end

		buffer.writeu8(out, offset, bEntry)
		offset += 1
	end

	trimReliable(offset)
end

local function readRows(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 2 > length then
		error("Rows: truncated")
	end

	local aLength: number = buffer.readu8(packet, cursor)

	if aLength > 3 then
		error("Rows.a: length out of range")
	end

	local bLength: number = buffer.readu8(packet, cursor + 1)

	if bLength > 4 then
		error("Rows.b: length out of range")
	end

	cursor += 2

	if cursor + 3 * aLength > length then
		error("Rows.a: truncated")
	end

	local a: { { id: number, name: string, tag: number? } } = table.create(aLength) :: { { id: number, name: string, tag: number? } }

	for index = 1, aLength do
		if cursor + 3 > length then
			error("Rows.a: truncated")
		end

		local flags: number = buffer.readu8(packet, cursor)
		local id: number = buffer.readu8(packet, cursor + 1)
		local nameLength: number = buffer.readu8(packet, cursor + 2)

		if nameLength > 4 then
			error("Rows.a[].name: length out of range")
		end

		local tag: number?
		cursor += 3

		if cursor + nameLength > length then
			error("Rows.a[].name: truncated")
		end

		local name: string = buffer.readstring(packet, cursor, nameLength)
		cursor += nameLength

		if bit32.btest(flags, 1) then
			if cursor + 2 > length then
				error("Rows.a[].tag: truncated")
			end

			local tag_2: number = buffer.readu16(packet, cursor)
			cursor += 2
			tag = tag_2
		end

		local aEntry = { id = id, name = name, tag = tag }
		a[index] = aEntry
	end

	if cursor + bLength > length then
		error("Rows.b: truncated")
	end

	local b: { number } = table.create(bLength) :: { number }

	for index_2 = 1, bLength do
		local bEntry: number = buffer.readu8(packet, cursor)
		cursor += 1
		b[index_2] = bEntry
	end

	return cursor, sideCursor, a, b
end

return {
	Records = { write = writeRecords, read = readRecords },
	Rows = { write = writeRows, read = readRows },
}
