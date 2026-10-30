local allocateReliable, slotReliable, refuseReliable = ...

export type Tree = { name: string, kids: { Tree } }
export type Folder = { entries: { Entry } }
export type Entry = { kind: "File", size: number } | { kind: "Sub", folder: Folder }

local ENTRY: { "File" | "Sub" } = { "File", "Sub" }

local writeTree: (allocate: (number) -> (number, buffer), slot: (any) -> (), refuse: (string) -> never, value: any, depth: number) -> ()

local readTree: (packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number, depth: number) -> (number, number, Tree)

local writeEntry: (allocate: (number) -> (number, buffer), slot: (any) -> (), refuse: (string) -> never, value: any, depth: number) -> ()

local readEntry: (packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number, depth: number) -> (number, number, Entry)

local writeFolder: (allocate: (number) -> (number, buffer), slot: (any) -> (), refuse: (string) -> never, value: any, depth: number) -> ()

local readFolder: (packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number, depth: number) -> (number, number, Folder)

function writeTree(allocate: (number) -> (number, buffer), slot: (any) -> (), refuse: (string) -> never, value: any, depth: number)
	if depth > 4 then
		refuse("Tree: nested deeper than 4")
	end

	local offset: number, out: buffer = allocate(2)

	if type(value) ~= "table" then
		refuse("Tree: expected table")
	end

	local name = value.name

	if type(name) ~= "string" then
		refuse("Tree.name: expected string")
	end

	if #name > 8 then
		refuse("Tree.name: length out of range")
	end

	buffer.writeu8(out, offset, #name)
	local kids = value.kids

	if type(kids) ~= "table" then
		refuse("Tree.kids: expected table")
	end

	if #kids > 3 then
		refuse("Tree.kids: length out of range")
	end

	buffer.writeu8(out, offset + 1, #kids)
	local nameOffset: number, nameOut: buffer = allocate(#name)
	buffer.writestring(nameOut, nameOffset, name)

	for index = 1, #kids do
		writeTree(allocate, slot, refuse, kids[index], depth + 1)
	end
end

function readTree(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number, depth: number): (number, number, Tree)
	if depth > 4 then
		error("Tree: nested deeper than 4")
	end

	if cursor + 2 > length then
		error("Tree: truncated")
	end

	local nameLength: number = buffer.readu8(packet, cursor)

	if nameLength > 8 then
		error("Tree.name: length out of range")
	end

	local kidsLength: number = buffer.readu8(packet, cursor + 1)

	if kidsLength > 3 then
		error("Tree.kids: length out of range")
	end

	cursor += 2

	if cursor + nameLength > length then
		error("Tree.name: truncated")
	end

	local name: string = buffer.readstring(packet, cursor, nameLength)
	cursor += nameLength

	if cursor + 2 * kidsLength > length then
		error("Tree.kids: truncated")
	end

	local kids: { Tree } = table.create(kidsLength) :: { Tree }

	for index = 1, kidsLength do
		local kidsEntry: Tree
		cursor, sideCursor, kidsEntry = readTree(packet, cursor, side, sideCursor, length, depth + 1)
		kids[index] = kidsEntry
	end

	local value = { name = name, kids = kids }

	return cursor, sideCursor, value
end

function writeEntry(allocate: (number) -> (number, buffer), slot: (any) -> (), refuse: (string) -> never, value: any, depth: number)
	if depth > 4 then
		refuse("Entry: nested deeper than 4")
	end

	local offset: number, out: buffer = allocate(1)
	local flags: number = 0

	if type(value) ~= "table" then
		refuse("Entry: expected table")
	end

	local valueIndex: number = table.find(ENTRY, value.kind) or 0

	if valueIndex == 0 then
		refuse("Entry: expected enum \"kind\" { File { size: u16 }, Sub { folder: Folder } }")
	end

	flags += valueIndex - 1
	buffer.writeu8(out, offset, flags)

	if valueIndex == 1 then
		local offset_2: number, out_2: buffer = allocate(2)
		local valueFile = value :: { kind: "File", size: number }
		local size = valueFile.size

		if type(size) ~= "number" or bit32.band(size, 65535) ~= size then
			refuse("Entry.size: expected u16")
		end

		buffer.writeu16(out_2, offset_2, size)
	elseif valueIndex == 2 then
		local valueSub = value :: { kind: "Sub", folder: Folder }
		writeFolder(allocate, slot, refuse, valueSub.folder, depth + 1)
	end
end

function readEntry(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number, depth: number): (number, number, Entry)
	if depth > 4 then
		error("Entry: nested deeper than 4")
	end

	if cursor + 1 > length then
		error("Entry: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local valueTag: number = bit32.extract(flags, 0, 1)
	local value: { kind: "File", size: number } | { kind: "Sub", folder: Folder }
	cursor += 1

	if valueTag == 0 then
		if cursor + 2 > length then
			error("Entry: truncated")
		end

		local size: number = buffer.readu16(packet, cursor)
		cursor += 2
		value = { kind = "File", size = size }
	elseif valueTag == 1 then
		local folder: Folder
		cursor, sideCursor, folder = readFolder(packet, cursor, side, sideCursor, length, depth + 1)
		value = { kind = "Sub", folder = folder }
	else
		error("Entry: out of range")
	end

	return cursor, sideCursor, value
end

function writeFolder(allocate: (number) -> (number, buffer), slot: (any) -> (), refuse: (string) -> never, value: any, depth: number)
	if depth > 4 then
		refuse("Folder: nested deeper than 4")
	end

	local offset: number, out: buffer = allocate(1)

	if type(value) ~= "table" then
		refuse("Folder: expected table")
	end

	local entries = value.entries

	if type(entries) ~= "table" then
		refuse("Folder.entries: expected table")
	end

	if #entries > 3 then
		refuse("Folder.entries: length out of range")
	end

	buffer.writeu8(out, offset, #entries)

	for index = 1, #entries do
		writeEntry(allocate, slot, refuse, entries[index], depth + 1)
	end
end

function readFolder(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number, depth: number): (number, number, Folder)
	if depth > 4 then
		error("Folder: nested deeper than 4")
	end

	if cursor + 1 > length then
		error("Folder: truncated")
	end

	local entriesLength: number = buffer.readu8(packet, cursor)

	if entriesLength > 3 then
		error("Folder.entries: length out of range")
	end

	cursor += 1

	if cursor + 2 * entriesLength > length then
		error("Folder.entries: truncated")
	end

	local entries: { Entry } = table.create(entriesLength) :: { Entry }

	for index = 1, entriesLength do
		local entriesEntry: Entry
		cursor, sideCursor, entriesEntry = readEntry(packet, cursor, side, sideCursor, length, depth + 1)
		entries[index] = entriesEntry
	end

	local value = { entries = entries }

	return cursor, sideCursor, value
end

local function writeScene(value: Tree)
	writeTree(allocateReliable, slotReliable, refuseReliable, value, 1)
end

local function readScene(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	local value: Tree
	cursor, sideCursor, value = readTree(packet, cursor, side, sideCursor, length, 1)

	return cursor, sideCursor, value
end

local function writeFiles(value: Folder)
	writeFolder(allocateReliable, slotReliable, refuseReliable, value, 1)
end

local function readFiles(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	local value: Folder
	cursor, sideCursor, value = readFolder(packet, cursor, side, sideCursor, length, 1)

	return cursor, sideCursor, value
end

return {
	Scene = { write = writeScene, read = readScene },
	Files = { write = writeFiles, read = readFiles },
}
