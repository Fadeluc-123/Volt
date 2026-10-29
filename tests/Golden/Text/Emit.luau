local beginReliable, allocateReliable, slotReliable, refuseReliable = ...

export type Note = { title: string, body: string }

local function writeNote(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(2)

	if type(value) ~= "table" then
		refuse("Note: expected table")
	end

	local title = value.title

	if type(title) ~= "string" then
		refuse("Note.title: expected string")
	end

	if #title < 1 or #title > 16 then
		refuse("Note.title: length out of range")
	end

	buffer.writeu8(out, offset, #title - 1)

	if utf8.len(title) == nil then
		refuse("Note.title: invalid UTF-8")
	end

	local body = value.body

	if type(body) ~= "string" then
		refuse("Note.body: expected string")
	end

	if #body > 64 then
		refuse("Note.body: length out of range")
	end

	buffer.writeu8(out, offset + 1, #body)

	if utf8.len(body) == nil then
		refuse("Note.body: invalid UTF-8")
	end

	local titleOffset: number, titleOut: buffer = allocate(#title)
	buffer.writestring(titleOut, titleOffset, title)
	local bodyOffset: number, bodyOut: buffer = allocate(#body)
	buffer.writestring(bodyOut, bodyOffset, body)
end

local function readNote(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Note)
	if cursor + 2 > length then
		error("Note: truncated")
	end

	local titleLength: number = 1 + buffer.readu8(packet, cursor)

	if titleLength > 16 then
		error("Note.title: length out of range")
	end

	local bodyLength: number = buffer.readu8(packet, cursor + 1)

	if bodyLength > 64 then
		error("Note.body: length out of range")
	end

	cursor += 2

	if cursor + titleLength > length then
		error("Note.title: truncated")
	end

	local title: string = buffer.readstring(packet, cursor, titleLength)
	cursor += titleLength

	if utf8.len(title) == nil then
		error("Note.title: invalid UTF-8")
	end

	if cursor + bodyLength > length then
		error("Note.body: truncated")
	end

	local body: string = buffer.readstring(packet, cursor, bodyLength)
	cursor += bodyLength

	if utf8.len(body) == nil then
		error("Note.body: invalid UTF-8")
	end

	local value = { title = title, body = body }

	return cursor, sideCursor, value
end

local function writeText(short: string, exact: string, free: string)
	local offset: number, out: buffer = beginReliable(7)

	if type(short) ~= "string" then
		refuseReliable("Text.short: expected string")
	end

	if #short < 1 or #short > 4 then
		refuseReliable("Text.short: length out of range")
	end

	buffer.writeu8(out, offset, #short - 1)

	if utf8.len(short) == nil then
		refuseReliable("Text.short: invalid UTF-8")
	end

	if type(exact) ~= "string" then
		refuseReliable("Text.exact: expected string")
	end

	if #exact ~= 4 then
		refuseReliable("Text.exact: expected 4 bytes")
	end

	if utf8.len(exact) == nil then
		refuseReliable("Text.exact: invalid UTF-8")
	end

	buffer.writestring(out, offset + 1, exact)

	if type(free) ~= "string" then
		refuseReliable("Text.free: expected string")
	end

	if #free > 65535 then
		refuseReliable("Text.free: length out of range")
	end

	buffer.writeu16(out, offset + 5, #free)

	if utf8.len(free) == nil then
		refuseReliable("Text.free: invalid UTF-8")
	end

	local shortOffset: number, shortOut: buffer = allocateReliable(#short)
	buffer.writestring(shortOut, shortOffset, short)
	local freeOffset: number, freeOut: buffer = allocateReliable(#free)
	buffer.writestring(freeOut, freeOffset, free)
end

local function readText(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 7 > length then
		error("Text: truncated")
	end

	local shortLength: number = 1 + buffer.readu8(packet, cursor)

	if shortLength > 4 then
		error("Text.short: length out of range")
	end

	local exact: string = buffer.readstring(packet, cursor + 1, 4)

	if utf8.len(exact) == nil then
		error("Text.exact: invalid UTF-8")
	end

	local freeLength: number = buffer.readu16(packet, cursor + 5)
	cursor += 7

	if cursor + shortLength > length then
		error("Text.short: truncated")
	end

	local short: string = buffer.readstring(packet, cursor, shortLength)
	cursor += shortLength

	if utf8.len(short) == nil then
		error("Text.short: invalid UTF-8")
	end

	if cursor + freeLength > length then
		error("Text.free: truncated")
	end

	local free: string = buffer.readstring(packet, cursor, freeLength)
	cursor += freeLength

	if utf8.len(free) == nil then
		error("Text.free: invalid UTF-8")
	end

	return cursor, sideCursor, short, exact, free
end

local function writeNotes(tags: { [string]: number }, first: Note, second: Note)
	local offset: number, out: buffer = beginReliable(1)

	if type(tags) ~= "table" then
		refuseReliable("Notes.tags: expected table")
	end

	local tagsCount: number = 0

	for _ in tags do
		tagsCount += 1
	end

	if tagsCount > 4 then
		refuseReliable("Notes.tags: length out of range")
	end

	buffer.writeu8(out, offset, tagsCount)

	for tagsKey, tagsValue in tags do
		local offset_2: number, out_2: buffer = allocateReliable(2)

		if type(tagsKey) ~= "string" then
			refuseReliable("Notes.tags[key]: expected string")
		end

		if #tagsKey < 1 or #tagsKey > 8 then
			refuseReliable("Notes.tags[key]: length out of range")
		end

		buffer.writeu8(out_2, offset_2, #tagsKey - 1)

		if utf8.len(tagsKey) == nil then
			refuseReliable("Notes.tags[key]: invalid UTF-8")
		end

		if type(tagsValue) ~= "number" or bit32.band(tagsValue, 255) ~= tagsValue then
			refuseReliable("Notes.tags[value]: expected u8")
		end

		buffer.writeu8(out_2, offset_2 + 1, tagsValue)
		local tagsKeyOffset: number, tagsKeyOut: buffer = allocateReliable(#tagsKey)
		buffer.writestring(tagsKeyOut, tagsKeyOffset, tagsKey)
	end

	writeNote(allocateReliable, slotReliable, refuseReliable, first)
	writeNote(allocateReliable, slotReliable, refuseReliable, second)
end

local function readNotes(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	if cursor + 1 > length then
		error("Notes: truncated")
	end

	local tagsLength: number = buffer.readu8(packet, cursor)

	if tagsLength > 4 then
		error("Notes.tags: length out of range")
	end

	local first: Note
	local second: Note
	cursor += 1

	if cursor + 3 * tagsLength > length then
		error("Notes.tags: truncated")
	end

	local tags: { [string]: number } = {}

	for _ = 1, tagsLength do
		if cursor + 2 > length then
			error("Notes.tags: truncated")
		end

		local tagsKeyLength: number = 1 + buffer.readu8(packet, cursor)

		if tagsKeyLength > 8 then
			error("Notes.tags[key]: length out of range")
		end

		local tagsValue: number = buffer.readu8(packet, cursor + 1)
		cursor += 2

		if cursor + tagsKeyLength > length then
			error("Notes.tags[key]: truncated")
		end

		local tagsKey: string = buffer.readstring(packet, cursor, tagsKeyLength)
		cursor += tagsKeyLength

		if utf8.len(tagsKey) == nil then
			error("Notes.tags[key]: invalid UTF-8")
		end

		if tags[tagsKey] ~= nil then
			error("Notes.tags: duplicate key")
		end

		tags[tagsKey] = tagsValue
	end

	cursor, sideCursor, first = readNote(packet, cursor, side, sideCursor, length)
	cursor, sideCursor, second = readNote(packet, cursor, side, sideCursor, length)

	return cursor, sideCursor, tags, first, second
end

return {
	Text = { write = writeText, read = readText },
	Notes = { write = writeNotes, read = readNotes },
}
