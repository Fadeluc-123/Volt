local beginReliable, allocateReliable, slotReliable, refuseReliable = ...

export type Reference = string
export type Team = "Red" | "Blue"

local TEAM: { string } = { "Red", "Blue" }

local function writeTeam(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(1)
	local flags: number = 0
	local valueIndex: number = table.find(TEAM, value) or 0

	if valueIndex == 0 then
		refuse("Team: expected enum { Red, Blue }")
	end

	flags += valueIndex - 1
	buffer.writeu8(out, offset, flags)
end

local function readTeam(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
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

local function writeOptionals(a: number?, b: string?, c: { n: number }?, d: boolean?, e: Reference?)
	local offset: number, out: buffer = beginReliable(1)
	local flags: number = 0
	flags += a ~= nil and 1 or 0
	flags += b ~= nil and 2 or 0
	flags += c ~= nil and 4 or 0
	flags += d ~= nil and 8 or 0
	flags += e ~= nil and 16 or 0
	buffer.writeu8(out, offset, flags)

	if a ~= nil then
		local offset_2: number, out_2: buffer = allocateReliable(1)

		if typeof(a) ~= "number" or a % 1 ~= 0 or a < 0 or a > 255 then
			refuseReliable("Optionals.a: expected u8")
		end

		buffer.writeu8(out_2, offset_2, a)
	end

	if b ~= nil then
		local offset_3: number, out_3: buffer = allocateReliable(1)

		if typeof(b) ~= "string" then
			refuseReliable("Optionals.b: expected string")
		end

		if #b > 8 then
			refuseReliable("Optionals.b: length out of range")
		end

		buffer.writeu8(out_3, offset_3, #b)
		local bOffset: number, bOut: buffer = allocateReliable(#b)
		buffer.writestring(bOut, bOffset, b)
	end

	if c ~= nil then
		local offset_4: number, out_4: buffer = allocateReliable(1)

		if typeof(c) ~= "table" then
			refuseReliable("Optionals.c: expected table")
		end

		if typeof(c.n) ~= "number" or c.n % 1 ~= 0 or c.n < 0 or c.n > 255 then
			refuseReliable("Optionals.c.n: expected u8")
		end

		buffer.writeu8(out_4, offset_4, c.n)
	end

	if d ~= nil then
		local offset_5: number, out_5: buffer = allocateReliable(1)
		local flags_2: number = 0

		if typeof(d) ~= "boolean" then
			refuseReliable("Optionals.d: expected boolean")
		end

		flags_2 += d and 1 or 0
		buffer.writeu8(out_5, offset_5, flags_2)
	end

	if e ~= nil then
		local offset_6: number, out_6: buffer = allocateReliable(1)

		if typeof(e) ~= "string" then
			refuseReliable("Optionals.e: expected string")
		end

		if #e < 1 or #e > 8 then
			refuseReliable("Optionals.e: length out of range")
		end

		buffer.writeu8(out_6, offset_6, #e - 1)
		local eOffset: number, eOut: buffer = allocateReliable(#e)
		buffer.writestring(eOut, eOffset, e)
	end
end

local function readOptionals(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 1 > length then
		error("Optionals: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local a
	local b
	local c
	local d
	local e
	cursor += 1

	if bit32.btest(flags, 1) then
		if cursor + 1 > length then
			error("Optionals.a: truncated")
		end

		local a_2: number = buffer.readu8(packet, cursor)
		cursor += 1
		a = a_2
	end

	if bit32.btest(flags, 2) then
		if cursor + 1 > length then
			error("Optionals.b: truncated")
		end

		local bLength: number = buffer.readu8(packet, cursor)

		if bLength > 8 then
			error("Optionals.b: length out of range")
		end

		cursor += 1

		if cursor + bLength > length then
			error("Optionals.b: truncated")
		end

		local b_2: string = buffer.readstring(packet, cursor, bLength)
		cursor += bLength
		b = b_2
	end

	if bit32.btest(flags, 4) then
		if cursor + 1 > length then
			error("Optionals.c: truncated")
		end

		local n: number = buffer.readu8(packet, cursor)
		cursor += 1
		local c_2 = { n = n }
		c = c_2
	end

	if bit32.btest(flags, 8) then
		if cursor + 1 > length then
			error("Optionals.d: truncated")
		end

		local flags_2: number = buffer.readu8(packet, cursor)
		cursor += 1
		d = bit32.btest(flags_2, 1)
	end

	if bit32.btest(flags, 16) then
		if cursor + 1 > length then
			error("Optionals.e: truncated")
		end

		local eLength: number = 1 + buffer.readu8(packet, cursor)

		if eLength > 8 then
			error("Optionals.e: length out of range")
		end

		cursor += 1

		if cursor + eLength > length then
			error("Optionals.e: truncated")
		end

		local e_2: string = buffer.readstring(packet, cursor, eLength)
		cursor += eLength
		e = e_2
	end

	return cursor, sideCursor, a, b, c, d, e
end

local function writeNested(value: { grid: { { number } }, slots: { { id: number, tag: Team? } }? })
	local offset: number, out: buffer = beginReliable(1)
	local flags: number = 0

	if typeof(value) ~= "table" then
		refuseReliable("Nested: expected table")
	end

	if typeof(value.grid) ~= "table" then
		refuseReliable("Nested.grid: expected table")
	end

	if #value.grid ~= 2 then
		refuseReliable("Nested.grid: expected 2 entries")
	end

	flags += value.slots ~= nil and 1 or 0
	buffer.writeu8(out, offset, flags)

	for index = 1, 2 do
		if typeof(value.grid[index]) ~= "table" then
			refuseReliable("Nested.grid[]: expected table")
		end

		if #value.grid[index] ~= 2 then
			refuseReliable("Nested.grid[]: expected 2 entries")
		end

		local gridEntryOffset: number, gridEntryOut: buffer = allocateReliable(2)

		for index_2 = 1, 2 do
			if typeof(value.grid[index][index_2]) ~= "number" or value.grid[index][index_2] % 1 ~= 0 or value.grid[index][index_2] < 0 or value.grid[index][index_2] > 255 then
				refuseReliable("Nested.grid[][]: expected u8")
			end

			buffer.writeu8(gridEntryOut, gridEntryOffset, value.grid[index][index_2])
			gridEntryOffset += 1
		end
	end

	if value.slots ~= nil then
		local offset_3: number, out_3: buffer = allocateReliable(1)

		if typeof(value.slots) ~= "table" then
			refuseReliable("Nested.slots: expected table")
		end

		if #value.slots > 3 then
			refuseReliable("Nested.slots: length out of range")
		end

		buffer.writeu8(out_3, offset_3, #value.slots)

		for index_3 = 1, #value.slots do
			local offset_4: number, out_4: buffer = allocateReliable(2)
			local flags_2: number = 0

			if typeof(value.slots[index_3]) ~= "table" then
				refuseReliable("Nested.slots[]: expected table")
			end

			if typeof(value.slots[index_3].id) ~= "number" or value.slots[index_3].id % 1 ~= 0 or value.slots[index_3].id < 0 or value.slots[index_3].id > 255 then
				refuseReliable("Nested.slots[].id: expected u8")
			end

			buffer.writeu8(out_4, offset_4 + 1, value.slots[index_3].id)
			flags_2 += value.slots[index_3].tag ~= nil and 1 or 0
			buffer.writeu8(out_4, offset_4, flags_2)

			if value.slots[index_3].tag ~= nil then
				writeTeam(allocateReliable, slotReliable, refuseReliable, value.slots[index_3].tag)
			end
		end
	end
end

local function readNested(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	if cursor + 1 > length then
		error("Nested: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local slots
	cursor += 1

	if cursor + 4 > length then
		error("Nested.grid: truncated")
	end

	local grid = table.create(2)

	for index = 1, 2 do
		if cursor + 2 > length then
			error("Nested.grid[]: truncated")
		end

		local gridEntry = table.create(2)

		for index_2 = 1, 2 do
			local gridEntryEntry: number = buffer.readu8(packet, cursor)
			cursor += 1
			gridEntry[index_2] = gridEntryEntry
		end

		grid[index] = gridEntry
	end

	if bit32.btest(flags, 1) then
		if cursor + 1 > length then
			error("Nested.slots: truncated")
		end

		local slotsLength: number = buffer.readu8(packet, cursor)

		if slotsLength > 3 then
			error("Nested.slots: length out of range")
		end

		cursor += 1

		if cursor + 2 * slotsLength > length then
			error("Nested.slots: truncated")
		end

		local slots_2 = table.create(slotsLength)

		for index_3 = 1, slotsLength do
			if cursor + 2 > length then
				error("Nested.slots: truncated")
			end

			local flags_2: number = buffer.readu8(packet, cursor)
			local id: number = buffer.readu8(packet, cursor + 1)
			local tag
			cursor += 2

			if bit32.btest(flags_2, 1) then
				local tag_2
				cursor, sideCursor, tag_2 = readTeam(packet, cursor, side, sideCursor, length)
				tag = tag_2
			end

			local slotsEntry = { id = id, tag = tag }
			slots_2[index_3] = slotsEntry
		end

		slots = slots_2
	end

	local value = { grid = grid, slots = slots }

	return cursor, sideCursor, value
end

return {
	Optionals = { write = writeOptionals, read = readOptionals },
	Nested = { write = writeNested, read = readNested },
}
