local beginReliable, allocateReliable, slotReliable, refuseReliable = ...

export type Stack = { item: string, quantity: number, properties: any? }
export type Team = "Red" | "Blue"

local TEAM: { "Red" | "Blue" } = { "Red", "Blue" }

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

local function readTeam(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Team)
	if cursor + 1 > length then
		error("Team: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local value: ("Red" | "Blue")? = TEAM[bit32.extract(flags, 0, 1) + 1]

	if not value then
		error("Team: out of range")
	end

	cursor += 1

	return cursor, sideCursor, value
end

local function writeUnions(a: number | string | boolean, b: Vector3 | Stack, c: Color3 | { number } | Team)
	local offset: number, out: buffer = beginReliable(1)
	local flags: number = 0
	local aMember: number = typeof(a) == "number" and 0 or typeof(a) == "string" and 1 or typeof(a) == "boolean" and 2 or -1

	if aMember < 0 then
		refuseReliable("Unions.a: expected u8 | string(0..4) | boolean")
	end

	flags += aMember
	local bMember: number = typeof(b) == "Vector3" and 0 or typeof(b) == "table" and 1 or -1

	if bMember < 0 then
		refuseReliable("Unions.b: expected Vector3 | Stack")
	end

	flags += bMember * 4
	local cMember: number = typeof(c) == "Color3" and 0 or typeof(c) == "table" and 1 or typeof(c) == "string" and 2 or -1

	if cMember < 0 then
		refuseReliable("Unions.c: expected Color3 | u8[0..3] | Team")
	end

	flags += cMember * 8
	buffer.writeu8(out, offset, flags)

	if aMember == 0 then
		local offset_2: number, out_2: buffer = allocateReliable(1)
		local a_2 = (a :: number)

		if bit32.band(a_2, 255) ~= a_2 then
			refuseReliable("Unions.a: expected u8")
		end

		buffer.writeu8(out_2, offset_2, a_2)
	elseif aMember == 1 then
		local offset_3: number, out_3: buffer = allocateReliable(1)
		local a_3 = (a :: string)

		if #a_3 > 4 then
			refuseReliable("Unions.a: length out of range")
		end

		buffer.writeu8(out_3, offset_3, #a_3)
		local aOffset: number, aOut: buffer = allocateReliable(#a_3)
		buffer.writestring(aOut, aOffset, a_3)
	elseif aMember == 2 then
		local offset_4: number, out_4: buffer = allocateReliable(1)
		local flags_2: number = 0
		local a_4 = (a :: boolean)
		flags_2 += a_4 and 1 or 0
		buffer.writeu8(out_4, offset_4, flags_2)
	end

	if bMember == 0 then
		local offset_5: number, out_5: buffer = allocateReliable(12)
		local b_2 = (b :: Vector3)
		local bX = b_2.X

		if bX ~= bX then
			refuseReliable("Unions.b.X: expected f32")
		end

		buffer.writef32(out_5, offset_5, bX)
		local bY = b_2.Y

		if bY ~= bY then
			refuseReliable("Unions.b.Y: expected f32")
		end

		buffer.writef32(out_5, offset_5 + 4, bY)
		local bZ = b_2.Z

		if bZ ~= bZ then
			refuseReliable("Unions.b.Z: expected f32")
		end

		buffer.writef32(out_5, offset_5 + 8, bZ)
	elseif bMember == 1 then
		writeStack(allocateReliable, slotReliable, refuseReliable, (b :: Stack))
	end

	if cMember == 0 then
		local offset_7: number, out_7: buffer = allocateReliable(3)
		local c_2 = (c :: Color3)
		buffer.writeu8(out_7, offset_7, math.round(c_2.R * 255))
		buffer.writeu8(out_7, offset_7 + 1, math.round(c_2.G * 255))
		buffer.writeu8(out_7, offset_7 + 2, math.round(c_2.B * 255))
	elseif cMember == 1 then
		local offset_8: number, out_8: buffer = allocateReliable(1)
		local c_3 = (c :: { number })

		if #c_3 > 3 then
			refuseReliable("Unions.c: length out of range")
		end

		buffer.writeu8(out_8, offset_8, #c_3)
		local cOffset: number, cOut: buffer = allocateReliable(#c_3)

		for index = 1, #c_3 do
			local cEntry = c_3[index]

			if type(cEntry) ~= "number" or bit32.band(cEntry, 255) ~= cEntry then
				refuseReliable("Unions.c[]: expected u8")
			end

			buffer.writeu8(cOut, cOffset, cEntry)
			cOffset += 1
		end
	elseif cMember == 2 then
		writeTeam(allocateReliable, slotReliable, refuseReliable, (c :: Team))
	end
end

local function readUnions(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	if cursor + 1 > length then
		error("Unions: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local aTag: number = bit32.extract(flags, 0, 2)
	local a: number | string | boolean
	local bTag: number = bit32.extract(flags, 2, 1)
	local b: Vector3 | Stack
	local cTag: number = bit32.extract(flags, 3, 2)
	local c: Color3 | { number } | Team
	cursor += 1

	if aTag == 0 then
		if cursor + 1 > length then
			error("Unions.a: truncated")
		end

		local a_2: number = buffer.readu8(packet, cursor)
		cursor += 1
		a = a_2 :: number
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
		a = a_3 :: string
	elseif aTag == 2 then
		if cursor + 1 > length then
			error("Unions.a: truncated")
		end

		local flags_2: number = buffer.readu8(packet, cursor)
		cursor += 1
		a = bit32.btest(flags_2, 1) :: boolean
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
		b = b_2 :: Vector3
	elseif bTag == 1 then
		local b_3: Stack
		cursor, sideCursor, b_3 = readStack(packet, cursor, side, sideCursor, length)
		b = b_3 :: Stack
	else
		error("Unions.b: out of range")
	end

	if cTag == 0 then
		if cursor + 3 > length then
			error("Unions.c: truncated")
		end

		local c_2: Color3 = Color3.fromRGB(buffer.readu8(packet, cursor), buffer.readu8(packet, cursor + 1), buffer.readu8(packet, cursor + 2))
		cursor += 3
		c = c_2 :: Color3
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

		local c_3: { number } = table.create(cLength) :: { number }

		for index = 1, cLength do
			local cEntry: number = buffer.readu8(packet, cursor)
			cursor += 1
			c_3[index] = cEntry
		end

		c = c_3 :: { number }
	elseif cTag == 2 then
		local c_4: Team
		cursor, sideCursor, c_4 = readTeam(packet, cursor, side, sideCursor, length)
		c = c_4 :: Team
	else
		error("Unions.c: out of range")
	end

	return cursor, sideCursor, a, b, c
end

return {
	Unions = { write = writeUnions, read = readUnions },
}
