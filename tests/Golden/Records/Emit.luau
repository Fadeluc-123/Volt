local beginReliable, allocateReliable, slotReliable, refuseReliable = ...

local function writeStack(allocate: (number) -> (number, buffer), slot: (any) -> (), refuse: (string) -> (), value: any)
	local offset: number, out: buffer = allocate(4)
	local flags: number = 0

	if typeof(value) ~= "table" then
		refuse("Stack: expected table")
	end

	if typeof(value.item) ~= "string" then
		refuse("Stack.item: expected string")
	end

	if #value.item < 1 or #value.item > 8 then
		refuse("Stack.item: length out of range")
	end

	buffer.writeu8(out, offset + 1, #value.item - 1)

	if typeof(value.quantity) ~= "number" or value.quantity % 1 ~= 0 or value.quantity < 1 or value.quantity > 999 then
		refuse("Stack.quantity: expected u16(1..999)")
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

local function writeSave(allocate: (number) -> (number, buffer), slot: (any) -> (), refuse: (string) -> (), value: any)
	local offset: number, out: buffer = allocate(3)

	if typeof(value) ~= "table" then
		refuse("Save: expected table")
	end

	if typeof(value.version) ~= "number" or value.version % 1 ~= 0 or value.version < 0 or value.version > 65535 then
		refuse("Save.version: expected u16")
	end

	buffer.writeu16(out, offset, value.version)

	if typeof(value.stacks) ~= "table" then
		refuse("Save.stacks: expected table")
	end

	if #value.stacks > 4 then
		refuse("Save.stacks: length out of range")
	end

	buffer.writeu8(out, offset + 2, #value.stacks)

	for index = 1, #value.stacks do
		writeStack(allocate, slot, refuse, value.stacks[index])
	end
end

local function readSave(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
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

	local stacks = table.create(stacksLength)

	for index = 1, stacksLength do
		local stacksEntry
		cursor, sideCursor, stacksEntry = readStack(packet, cursor, side, sideCursor, length)
		stacks[index] = stacksEntry
	end

	local value = { version = version, stacks = stacks }

	return cursor, sideCursor, value
end

local function writeRecords(a: any, b: any, c: any, d: any)
	local offset: number, out: buffer = beginReliable(3)
	local flags: number = 0

	if typeof(a) ~= "table" then
		refuseReliable("Records.a: expected table")
	end

	if typeof(a.x) ~= "number" or a.x % 1 ~= 0 or a.x < 0 or a.x > 255 then
		refuseReliable("Records.a.x: expected u8")
	end

	buffer.writeu8(out, offset + 1, a.x)

	if typeof(a.y) ~= "string" then
		refuseReliable("Records.a.y: expected string")
	end

	if #a.y > 4 then
		refuseReliable("Records.a.y: length out of range")
	end

	buffer.writeu8(out, offset + 2, #a.y)

	if typeof(a.z) ~= "boolean" then
		refuseReliable("Records.a.z: expected boolean")
	end

	flags += a.z and 1 or 0

	if typeof(b) ~= "table" then
		refuseReliable("Records.b: expected table")
	end

	buffer.writeu8(out, offset, flags)
	local yOffset: number, yOut: buffer = allocateReliable(#a.y)
	buffer.writestring(yOut, yOffset, a.y)
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

	local c
	local d
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

return {
	Records = { write = writeRecords, read = readRecords },
}
