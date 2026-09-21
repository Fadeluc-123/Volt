local allocateReliable, slotReliable = ...

local TEAM: { string } = { "Red", "Blue" }

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

local function writeUnions(a: any, b: any, c: any)
	local offset: number, out: buffer = allocateReliable(1)
	local flags: number = 0
	local aMember: number? = typeof(a) == "number" and 0 or typeof(a) == "string" and 1 or typeof(a) == "boolean" and 2 or nil

	if not aMember then
		error("Unions.a: expected u8 | string(0..4) | boolean")
	end

	flags += aMember
	local bMember: number? = typeof(b) == "Vector3" and 0 or typeof(b) == "table" and 1 or nil

	if not bMember then
		error("Unions.b: expected Vector3 | Stack")
	end

	flags += bMember * 4
	local cMember: number? = typeof(c) == "Color3" and 0 or typeof(c) == "table" and 1 or typeof(c) == "string" and 2 or nil

	if not cMember then
		error("Unions.c: expected Color3 | u8[0..3] | Team")
	end

	flags += cMember * 8
	buffer.writeu8(out, offset, flags)

	if aMember == 0 then
		local offset_2: number, out_2: buffer = allocateReliable(1)

		if a % 1 ~= 0 or a < 0 or a > 255 then
			error("Unions.a: expected u8")
		end

		buffer.writeu8(out_2, offset_2, a)
	elseif aMember == 1 then
		local offset_3: number, out_3: buffer = allocateReliable(1)

		if #a > 4 then
			error("Unions.a: length out of range")
		end

		buffer.writeu8(out_3, offset_3, #a)
		local aOffset: number, aOut: buffer = allocateReliable(#a)
		buffer.writestring(aOut, aOffset, a)
	elseif aMember == 2 then
		local offset_4: number, out_4: buffer = allocateReliable(1)
		local flags_2: number = 0
		flags_2 += a and 1 or 0
		buffer.writeu8(out_4, offset_4, flags_2)
	end

	if bMember == 0 then
		local offset_5: number, out_5: buffer = allocateReliable(12)

		if b.X ~= b.X then
			error("Unions.b.X: expected f32")
		end

		buffer.writef32(out_5, offset_5, b.X)

		if b.Y ~= b.Y then
			error("Unions.b.Y: expected f32")
		end

		buffer.writef32(out_5, offset_5 + 4, b.Y)

		if b.Z ~= b.Z then
			error("Unions.b.Z: expected f32")
		end

		buffer.writef32(out_5, offset_5 + 8, b.Z)
	elseif bMember == 1 then
		writeStack(allocateReliable, slotReliable, b)
	end

	if cMember == 0 then
		local offset_7: number, out_7: buffer = allocateReliable(3)
		buffer.writeu8(out_7, offset_7, math.round(c.R * 255))
		buffer.writeu8(out_7, offset_7 + 1, math.round(c.G * 255))
		buffer.writeu8(out_7, offset_7 + 2, math.round(c.B * 255))
	elseif cMember == 1 then
		local offset_8: number, out_8: buffer = allocateReliable(1)

		if #c > 3 then
			error("Unions.c: length out of range")
		end

		buffer.writeu8(out_8, offset_8, #c)
		local cOffset: number, cOut: buffer = allocateReliable(#c)

		for index = 1, #c do
			if typeof(c[index]) ~= "number" or c[index] % 1 ~= 0 or c[index] < 0 or c[index] > 255 then
				error("Unions.c[]: expected u8")
			end

			buffer.writeu8(cOut, cOffset, c[index])
			cOffset += 1
		end
	elseif cMember == 2 then
		writeTeam(allocateReliable, slotReliable, c)
	end
end

local function readUnions(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	if cursor + 1 > length then
		error("Unions: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local aTag: number = bit32.extract(flags, 0, 2)
	local a
	local bTag: number = bit32.extract(flags, 2, 1)
	local b
	local cTag: number = bit32.extract(flags, 3, 2)
	local c
	cursor += 1

	if aTag == 0 then
		if cursor + 1 > length then
			error("Unions.a: truncated")
		end

		local a_2: number = buffer.readu8(packet, cursor)
		cursor += 1
		a = a_2
	elseif aTag == 1 then
		if cursor + 1 > length then
			error("Unions.a: truncated")
		end

		local aLength: number = buffer.readu8(packet, cursor)

		if aLength > 4 then
			error("Unions.a: length out of range")
		end

		cursor += 1

		if cursor + aLength > length then
			error("Unions.a: truncated")
		end

		local a_3: string = buffer.readstring(packet, cursor, aLength)
		cursor += aLength
		a = a_3
	elseif aTag == 2 then
		if cursor + 1 > length then
			error("Unions.a: truncated")
		end

		local flags_2: number = buffer.readu8(packet, cursor)
		cursor += 1
		a = bit32.btest(flags_2, 1)
	else
		error("Unions.a: out of range")
	end

	if bTag == 0 then
		if cursor + 12 > length then
			error("Unions.b: truncated")
		end

		local bX: number = buffer.readf32(packet, cursor)

		if bX ~= bX then
			error("Unions.b.X: out of range")
		end

		local bY: number = buffer.readf32(packet, cursor + 4)

		if bY ~= bY then
			error("Unions.b.Y: out of range")
		end

		local bZ: number = buffer.readf32(packet, cursor + 8)

		if bZ ~= bZ then
			error("Unions.b.Z: out of range")
		end

		local b_2: Vector3 = Vector3.new(bX, bY, bZ)
		cursor += 12
		b = b_2
	elseif bTag == 1 then
		local b_3
		cursor, sideCursor, b_3 = readStack(packet, cursor, side, sideCursor, length)
		b = b_3
	else
		error("Unions.b: out of range")
	end

	if cTag == 0 then
		if cursor + 3 > length then
			error("Unions.c: truncated")
		end

		local c_2: Color3 = Color3.fromRGB(buffer.readu8(packet, cursor), buffer.readu8(packet, cursor + 1), buffer.readu8(packet, cursor + 2))
		cursor += 3
		c = c_2
	elseif cTag == 1 then
		if cursor + 1 > length then
			error("Unions.c: truncated")
		end

		local cLength: number = buffer.readu8(packet, cursor)

		if cLength > 3 then
			error("Unions.c: length out of range")
		end

		cursor += 1

		if cursor + cLength > length then
			error("Unions.c: truncated")
		end

		local c_3 = table.create(cLength)

		for index = 1, cLength do
			local cEntry: number = buffer.readu8(packet, cursor)
			cursor += 1
			c_3[index] = cEntry
		end

		c = c_3
	elseif cTag == 2 then
		local c_4
		cursor, sideCursor, c_4 = readTeam(packet, cursor, side, sideCursor, length)
		c = c_4
	else
		error("Unions.c: out of range")
	end

	return cursor, sideCursor, a, b, c
end

return {
	Unions = { write = writeUnions, read = readUnions },
}
