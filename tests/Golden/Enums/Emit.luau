local allocateReliable, slotReliable = ...

local TEAM: { string } = { "Red", "Blue" }

local ENUMS_B: { string } = { "X" }

local ENUMS_C: { string } = { "Move", "Stop", "Say" }

local ENUMS_D: { string } = { "Red", "Blue", "Green" }

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

local function writeEnums(a: any, b: any, c: any, d: any)
	local offset: number, out: buffer = allocateReliable(1)
	local flags: number = 0
	local bIndex: number? = table.find(ENUMS_B, b)

	if not bIndex then
		error("Enums.b: expected enum { X }")
	end

	if typeof(c) ~= "table" then
		error("Enums.c: expected table")
	end

	local cIndex: number? = table.find(ENUMS_C, c.kind)

	if not cIndex then
		error("Enums.c: expected enum \"kind\" { Move { dx: i8, dy: i8 }, Stop, Say { text: string(0..16) } }")
	end

	flags += cIndex - 1
	local dIndex: number? = table.find(ENUMS_D, d)

	if not dIndex then
		error("Enums.d: expected enum { Red, Blue, Green }")
	end

	flags += (dIndex - 1) * 4
	buffer.writeu8(out, offset, flags)
	writeTeam(allocateReliable, slotReliable, a)

	if cIndex == 1 then
		local offset_2: number, out_2: buffer = allocateReliable(2)

		if typeof(c.dx) ~= "number" or c.dx % 1 ~= 0 or c.dx < -128 or c.dx > 127 then
			error("Enums.c.dx: expected i8")
		end

		buffer.writei8(out_2, offset_2, c.dx)

		if typeof(c.dy) ~= "number" or c.dy % 1 ~= 0 or c.dy < -128 or c.dy > 127 then
			error("Enums.c.dy: expected i8")
		end

		buffer.writei8(out_2, offset_2 + 1, c.dy)
	elseif cIndex == 3 then
		local offset_4: number, out_4: buffer = allocateReliable(1)

		if typeof(c.text) ~= "string" then
			error("Enums.c.text: expected string")
		end

		if #c.text > 16 then
			error("Enums.c.text: length out of range")
		end

		buffer.writeu8(out_4, offset_4, #c.text)
		local textOffset: number, textOut: buffer = allocateReliable(#c.text)
		buffer.writestring(textOut, textOffset, c.text)
	end
end

local function readEnums(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	if cursor + 1 > length then
		error("Enums: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local a
	local b: string? = ENUMS_B[1]

	if not b then
		error("Enums.b: out of range")
	end

	local cTag: number = bit32.extract(flags, 0, 2)
	local c
	local d: string? = ENUMS_D[bit32.extract(flags, 2, 2) + 1]

	if not d then
		error("Enums.d: out of range")
	end

	cursor += 1
	cursor, sideCursor, a = readTeam(packet, cursor, side, sideCursor, length)

	if cTag == 0 then
		if cursor + 2 > length then
			error("Enums.c: truncated")
		end

		local dx: number = buffer.readi8(packet, cursor)
		local dy: number = buffer.readi8(packet, cursor + 1)
		cursor += 2
		c = { kind = "Move", dx = dx, dy = dy }
	elseif cTag == 1 then
		c = { kind = "Stop" }
	elseif cTag == 2 then
		if cursor + 1 > length then
			error("Enums.c: truncated")
		end

		local textLength: number = buffer.readu8(packet, cursor)

		if textLength > 16 then
			error("Enums.c.text: length out of range")
		end

		cursor += 1

		if cursor + textLength > length then
			error("Enums.c.text: truncated")
		end

		local text: string = buffer.readstring(packet, cursor, textLength)
		cursor += textLength
		c = { kind = "Say", text = text }
	else
		error("Enums.c: out of range")
	end

	return cursor, sideCursor, a, b, c, d
end

return {
	Enums = { write = writeEnums, read = readEnums },
}
