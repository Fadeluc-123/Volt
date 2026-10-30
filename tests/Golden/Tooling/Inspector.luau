--[[
    The packet inspector Volt 0.1.0 generated from Tooling.volt: the
    function PacketProfiler calls for each packet on the Tooling scope's
    remotes, reading every message with the checks its receiving side
    reads with. Generated code: change the schema and run volt again
    rather than editing this file
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type Kind = "Info" | "Warn"
type Entry = { name: string, kind: Kind }

type Bot = { Name: string }

local runtime = {
	calls = {} :: { { Name: string, Arguments: { any } } },
	reading = "",

	note = function (self: any, name: string, cursor: number, sideCursor: number, ...: any): (number, number)
		table.insert(self.calls, { Name = name, Arguments = { ... } })

		return cursor, sideCursor
	end,

	deliver = function (self: any, _: number, _: any, cursor: number, sideCursor: number, ...: any): (number, number)
		return self:note(self.reading, cursor, sideCursor, ...)
	end,

	await = function (self: any, _: number, _: buffer, _: number, cursor: number, _: { any }, _: number, sideCursor: number, ...: any): (number, number)
		return self:note(self.reading, cursor, sideCursor, ...)
	end,

	ordered = function (self: any, _: number, sequence: number, _: any, cursor: number, sideCursor: number, ...: any): (number, number)
		return self:note(self.reading, cursor, sideCursor, sequence, ...)
	end,

	merge = function (_: any, _: number, mask: number, partial: { [string]: any }): (number, { [string]: any })
		return mask, partial
	end,

	call = function (self: any, _: number, _: any, _: number, cursor: number, sideCursor: number, ...: any): (number, number)
		return self:note(`{self.reading} (call)`, cursor, sideCursor, ...)
	end,

	reply = function (self: any, _: number, _: any, _: number, cursor: number, sideCursor: number, ...: any): (number, number)
		return self:note(`{self.reading} (reply)`, cursor, sideCursor, true, ...)
	end,

	refused = function (self: any, _: number, _: any, _: number, status: number, packet: buffer, cursor: number, sideCursor: number, length: number): (number, number)
		if status > 3 then
			error(`{self.reading}: unknown status {status}`)
		end

		if cursor + 2 > length then
			error(`{self.reading}: truncated`)
		end

		local count: number = buffer.readu16(packet, cursor)
		cursor += 2

		if count > 256 or cursor + count > length then
			error(`{self.reading}: truncated`)
		end

		return self:note(`{self.reading} (reply)`, cursor + count, sideCursor, false, buffer.readstring(packet, cursor, count))
	end,
}

local ENTRY_KIND: { "Info" | "Warn" } = { "Info", "Warn" }

local function readEntry(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Entry)
	if cursor + 2 > length then
		error("Entry: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local nameLength: number = 1 + buffer.readu8(packet, cursor + 1)

	if nameLength > 16 then
		error("Entry.name: length out of range")
	end

	local kind: ("Info" | "Warn")? = ENTRY_KIND[bit32.extract(flags, 0, 1) + 1]

	if not kind then
		error("Entry.kind: out of range")
	end

	cursor += 2

	if cursor + nameLength > length then
		error("Entry.name: truncated")
	end

	local name: string = buffer.readstring(packet, cursor, nameLength)
	cursor += nameLength
	local value = { name = name, kind = kind }

	return cursor, sideCursor, value
end

local messages: { [string]: { [number]: { name: string, read: (player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number) -> (number, number) } } } = {
	server = {
		[1] = {
			name = "Sync",
			read = function (player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
				if cursor + 1 > length then
					error("Sync: truncated")
				end

				local value: number = buffer.readu8(packet, cursor)
				cursor += 1

				return runtime:deliver(1, player, cursor, sideCursor, value)
			end,
		},

		[2] = {
			name = "Post",
			read = function (player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
				local value: Entry
				cursor, sideCursor, value = readEntry(packet, cursor, side, sideCursor, length)

				return runtime:deliver(2, player, cursor, sideCursor, value)
			end,
		},

		[3] = {
			name = "Lookup",
			read = function (player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
				if cursor + 3 > length then
					error("Lookup: truncated")
				end

				local slot: number = buffer.readu16(packet, cursor)
				local valueLength: number = 1 + buffer.readu8(packet, cursor + 2)

				if valueLength > 16 then
					error("Lookup: length out of range")
				end

				cursor += 3

				if cursor + valueLength > length then
					error("Lookup: truncated")
				end

				local value: string = buffer.readstring(packet, cursor, valueLength)
				cursor += valueLength

				return runtime:call(3, player, slot, cursor, sideCursor, value)
			end,
		},
	},

	client = {
		[1] = {
			name = "Sync",
			read = function (player: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)
				if cursor + 1 > length then
					error("Sync: truncated")
				end

				local value: number = buffer.readu8(packet, cursor)
				cursor += 1

				return runtime:deliver(1, player, cursor, sideCursor, value)
			end,
		},

		[2] = {
			name = "Seen",
			read = function (player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
				local who: Instance? = side[sideCursor]
				sideCursor += 1

				if typeof(who) ~= "Instance" then
					error("Seen.who: expected Instance")
				end

				local entry: Entry
				cursor, sideCursor, entry = readEntry(packet, cursor, side, sideCursor, length)

				return runtime:deliver(2, player, cursor, sideCursor, who, entry)
			end,
		},

		[3] = {
			name = "Lookup",
			read = function (player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number)
				if cursor + 3 > length then
					error("Lookup: truncated")
				end

				local slot: number = buffer.readu16(packet, cursor)
				local status: number = buffer.readu8(packet, cursor + 2)
				cursor += 3

				if status == 0 then
					if cursor + 1 > length then
						error("Lookup: truncated")
					end

					local flags: number = buffer.readu8(packet, cursor)
					local value: Entry?
					cursor += 1

					if bit32.btest(flags, 1) then
						local value_2: Entry
						cursor, sideCursor, value_2 = readEntry(packet, cursor, side, sideCursor, length)
						value = value_2
					end

					return runtime:reply(3, player, slot, cursor, sideCursor, value)
				end

				return runtime:refused(3, player, slot, status, packet, cursor, sideCursor, length)
			end,
		},
	},
}

local function read(server: boolean, player: any, packet: buffer, side: { any })
	local length: number = buffer.len(packet)
	local found = server and messages.server or messages.client
	local width: number = 1
	local cursor: number, sideCursor: number = 0, 1

	if server and cursor + 5 <= length and buffer.readu8(packet, cursor) == 0 then
		runtime:note("Volt handshake", cursor, sideCursor, buffer.readu32(packet, cursor + 1))
		cursor += 5
	end

	while cursor < length do
		if cursor + width > length then
			error("truncated message id")
		end

		local id: number = buffer.readu8(packet, cursor)
		local message = found[id]

		if message == nil then
			error(`unknown message {id}`)
		end

		runtime.reading = message.name
		cursor, sideCursor = message.read(player, packet, cursor + width, side, sideCursor, length)
		runtime.reading = ""
	end
end

return function (remote: Instance, ...: any): { { Name: string, Arguments: { any } } }?
	local folder: Instance? = ReplicatedStorage:FindFirstChild("Volt")
	local scope: Instance? = folder and folder:FindFirstChild("Tooling")

	if scope == nil or remote.Parent ~= scope then
		return nil
	end

	local first: any, second: any, third: any = ...
	local server: boolean = typeof(first) ~= "buffer"
	local player: any, packet: any, side: any = nil, first, second

	if server then
		player, packet, side = first, second, third
	end

	runtime.calls, runtime.reading = {}, ""

	local ok: boolean, problem: any = pcall(read, server, player, packet, side or {})

	if not ok then
		local detail: string = (tostring(problem):gsub("^.-:%d+: ", ""))
		runtime:note(#runtime.reading == 0 and `packet: {detail}` or `decode: {runtime.reading}`, 0, 0, detail)
	end

	return runtime.calls
end
