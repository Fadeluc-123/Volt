local beginReliable, allocateReliable, slotReliable, refuseReliable = ...

export type Pair<A, B> = { first: A, second: B }
export type Maybe<T> = T?
type Box<T> = { value: T, spare: { T } }
export type Scores = Pair<number, number>

local function writeScores(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(4)

	if type(value) ~= "table" then
		refuse("Scores: expected table")
	end

	local first = value.first

	if type(first) ~= "number" or bit32.band(first, 65535) ~= first then
		refuse("Scores.first: expected u16")
	end

	buffer.writeu16(out, offset, first)
	local second = value.second

	if type(second) ~= "number" or bit32.band(second, 65535) ~= second then
		refuse("Scores.second: expected u16")
	end

	buffer.writeu16(out, offset + 2, second)
end

local function readScores(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Scores)
	if cursor + 4 > length then
		error("Scores: truncated")
	end

	local first: number = buffer.readu16(packet, cursor)
	local second: number = buffer.readu16(packet, cursor + 2)
	cursor += 4
	local value = { first = first, second = second }

	return cursor, sideCursor, value
end

local function writePair_2(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(2)

	if type(value) ~= "table" then
		refuse("Pair<u8, u8>: expected table")
	end

	local first = value.first

	if type(first) ~= "number" or bit32.band(first, 255) ~= first then
		refuse("Pair<u8, u8>.first: expected u8")
	end

	buffer.writeu8(out, offset, first)
	local second = value.second

	if type(second) ~= "number" or bit32.band(second, 255) ~= second then
		refuse("Pair<u8, u8>.second: expected u8")
	end

	buffer.writeu8(out, offset + 1, second)
end

local function readPair_2(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Pair<number, number>)
	if cursor + 2 > length then
		error("Pair<u8, u8>: truncated")
	end

	local first: number = buffer.readu8(packet, cursor)
	local second: number = buffer.readu8(packet, cursor + 1)
	cursor += 2
	local value = { first = first, second = second }

	return cursor, sideCursor, value
end

local function writeMoves(a: Pair<number, number>, b: Maybe<Pair<number, number>>, c: Pair<number, string>)
	local offset: number, out: buffer = beginReliable(4)
	local flags: number = 0
	flags += b ~= nil and 1 or 0

	if type(c) ~= "table" then
		refuseReliable("Moves.c: expected table")
	end

	local first = c.first

	if type(first) ~= "number" or bit32.band(first, 65535) ~= first then
		refuseReliable("Moves.c.first: expected u16")
	end

	buffer.writeu16(out, offset + 1, first)
	local second = c.second

	if type(second) ~= "string" then
		refuseReliable("Moves.c.second: expected string")
	end

	if #second > 4 then
		refuseReliable("Moves.c.second: length out of range")
	end

	buffer.writeu8(out, offset + 3, #second)
	buffer.writeu8(out, offset, flags)
	writePair_2(allocateReliable, slotReliable, refuseReliable, a)

	if b ~= nil then
		writePair_2(allocateReliable, slotReliable, refuseReliable, b)
	end

	local secondOffset: number, secondOut: buffer = allocateReliable(#second)
	buffer.writestring(secondOut, secondOffset, second)
end

local function readMoves(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	if cursor + 4 > length then
		error("Moves: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local a: Pair<number, number>
	local b: Pair<number, number>?
	local first: number = buffer.readu16(packet, cursor + 1)
	local secondLength: number = buffer.readu8(packet, cursor + 3)

	if secondLength > 4 then
		error("Moves.c.second: length out of range")
	end

	cursor += 4
	cursor, sideCursor, a = readPair_2(packet, cursor, side, sideCursor, length)

	if bit32.btest(flags, 1) then
		local b_2: Pair<number, number>
		cursor, sideCursor, b_2 = readPair_2(packet, cursor, side, sideCursor, length)
		b = b_2
	end

	if cursor + secondLength > length then
		error("Moves.c.second: truncated")
	end

	local second: string = buffer.readstring(packet, cursor, secondLength)
	cursor += secondLength
	local c = { first = first, second = second }

	return cursor, sideCursor, a, b, c
end

local function writeBoxes(a: Box<number>, b: Scores)
	local offset: number, out: buffer = beginReliable(2)

	if type(a) ~= "table" then
		refuseReliable("Boxes.a: expected table")
	end

	local value = a.value

	if type(value) ~= "number" or bit32.band(value, 255) ~= value then
		refuseReliable("Boxes.a.value: expected u8")
	end

	buffer.writeu8(out, offset, value)
	local spare = a.spare

	if type(spare) ~= "table" then
		refuseReliable("Boxes.a.spare: expected table")
	end

	if #spare > 2 then
		refuseReliable("Boxes.a.spare: length out of range")
	end

	buffer.writeu8(out, offset + 1, #spare)
	local spareOffset: number, spareOut: buffer = allocateReliable(#spare)

	for index = 1, #spare do
		local spareEntry = spare[index]

		if type(spareEntry) ~= "number" or bit32.band(spareEntry, 255) ~= spareEntry then
			refuseReliable("Boxes.a.spare[]: expected u8")
		end

		buffer.writeu8(spareOut, spareOffset, spareEntry)
		spareOffset += 1
	end

	writeScores(allocateReliable, slotReliable, refuseReliable, b)
end

local function readBoxes(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	if cursor + 2 > length then
		error("Boxes: truncated")
	end

	local value: number = buffer.readu8(packet, cursor)
	local spareLength: number = buffer.readu8(packet, cursor + 1)

	if spareLength > 2 then
		error("Boxes.a.spare: length out of range")
	end

	local b: Scores
	cursor += 2

	if cursor + spareLength > length then
		error("Boxes.a.spare: truncated")
	end

	local spare: { number } = table.create(spareLength) :: { number }

	for index = 1, spareLength do
		local spareEntry: number = buffer.readu8(packet, cursor)
		cursor += 1
		spare[index] = spareEntry
	end

	local a = { value = value, spare = spare }
	cursor, sideCursor, b = readScores(packet, cursor, side, sideCursor, length)

	return cursor, sideCursor, a, b
end

return {
	Moves = { write = writeMoves, read = readMoves },
	Boxes = { write = writeBoxes, read = readBoxes },
}
