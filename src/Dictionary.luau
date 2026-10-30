--[[
    The string dictionary, merged onto the runtime: the server gives a
    string an id the first time a message names it and sends each player
    the entries they lack ahead of their default stream's next packet,
    and the client reads them into the list its readers index
--]]

--!strict
local Dictionary = {}

local Config = require("./Config/Runtime")
local States = require("./Send/States")
local Types = require("./Config/Types/Runtime")

type Joined = Types.Joined
type Message = Types.Message
type Runtime = Types.Runtime
type State = Types.State

local ENTRIES: number = Config.dictionaryEntries

local NAME: string = "Volt.dictionary" -- What the dictionary message's failures are named; no declaration may be Volt
local ID: number = 0 -- The dictionary message's id toward the client, which no message there takes
local HEADER_BYTES: number = 4 -- After the id: the id of its first entry, then how many follow, a u16 each
local LENGTH_BYTES: number = 1 -- Each entry's length ahead of its bytes, a u8

-- Whiteoak TODO: The dictionary never shrinks and stops at a fixed capacity, so a string no message names any more
-- keeps its entry; letting entries go would need every client told which ids are free again

--[[
    The dictionary message holding every entry after the ones a player
    holds: the id, as wide as an id toward the client, the id of its
    first entry, how many follow, then each entry's length and bytes
--]]

local function message(entries: { string }, held: number, width: number): buffer
	local bytes: number = width + HEADER_BYTES
	local cursor: number = bytes

	for index: number = held + 1, #entries do
		bytes += LENGTH_BYTES + #entries[index]
	end

	-- A new buffer is all zeros, which is the id already, at either width
	local out: buffer = buffer.create(bytes)

	buffer.writeu16(out, width, held + 1)
	buffer.writeu16(out, width + 2, #entries - held)

	for index: number = held + 1, #entries do
		local entry: string = entries[index]

		buffer.writeu8(out, cursor, #entry)
		buffer.writestring(out, cursor + LENGTH_BYTES, entry)
		cursor += LENGTH_BYTES + #entry
	end

	return out
end

--[[
    On a client whose schema has a dictionary, reads id 0 as the server's
    dictionary message through a row of the runtime's own, which names
    its failures; a server hears no id 0 past the handshake
--]]

function Dictionary.hear(self: Runtime)
	if self._server or not self._dictionaryBytes then
		return
	end

	local messages: { [number]: Message } = table.clone(self._messages)

	messages[ID] = {
		name = NAME,
		kind = "dictionary",

		read = function (
			_: any,
			packet: buffer,
			cursor: number,
			_: { any },
			sideCursor: number,
			length: number
		): (number, number)
			return self:_learn(packet, cursor, length), sideCursor
		end,
	}

	self._messages = messages
end

-- A string's id: its own once it has one, the next when there is room, and 0 when the dictionary is full
function Dictionary._intern(self: Runtime, value: string): number
	local id: number? = self._ids[value]
	if id then
		return id
	end

	local entries: { string } = self.dictionary
	if #entries >= ENTRIES then
		return 0
	end

	table.insert(entries, value)
	self._ids[value] = #entries

	return #entries
end

--[[
    Fires the dictionary message just ahead of a packet of a player's
    default stream when they lack entries: a packet of its own, opening
    as that stream's packets do, counted as one message, one packet and
    its bytes. Players holding as many entries share one message
--]]

function Dictionary._lead(self: Runtime, target: any)
	local joined: Joined? = self._players[target]
	local count: number = #self.dictionary

	if not joined or joined.known >= count then
		return
	end

	-- Each message runs to the last entry, so all are built again once the dictionary grows
	if self._owedTo ~= count then
		table.clear(self._owed)
		self._owedTo = count
	end

	local held: number = joined.known
	local owed: buffer = self._owed[held] or message(self.dictionary, held, self._dictionaryBytes :: number)
	local state: State = States.blank(target, joined.stats, joined.reliable.record, false)

	self._owed[held] = owed
	state.out = owed

	-- Known first, so the packet's own fire goes straight through to the transport
	joined.known = count
	joined.stats.messagesOut += 1
	self._stats.messagesOut += 1
	self.reliable:_packet(target, state, 0, buffer.len(owed), 1, 1)
end

--[[
    The client's reader of the dictionary message: checks all of it, the
    header whole, the first id the one after the last held, at least one
    entry, the total within capacity and every entry within the packet,
    before it takes any entry. Returns the cursor past it
--]]

function Dictionary._learn(self: Runtime, packet: buffer, cursor: number, length: number): number
	local entries: { string } = self.dictionary
	local held: number = #entries

	if cursor + HEADER_BYTES > length then
		error(`{NAME}: truncated`, 0)
	end

	local first: number = buffer.readu16(packet, cursor)
	local count: number = buffer.readu16(packet, cursor + 2)

	cursor += HEADER_BYTES

	if first ~= held + 1 then
		error(`{NAME}: out of order`, 0)
	end

	if count == 0 then
		error(`{NAME}: no entries`, 0)
	end

	if held + count > ENTRIES then
		error(`{NAME}: past {ENTRIES} entries`, 0)
	end

	local taken: { string } = {}

	for index: number = 1, count do
		if cursor + LENGTH_BYTES > length then
			error(`{NAME}: truncated`, 0)
		end

		local bytes: number = buffer.readu8(packet, cursor)
		cursor += LENGTH_BYTES

		if cursor + bytes > length then
			error(`{NAME}: truncated`, 0)
		end

		taken[index] = buffer.readstring(packet, cursor, bytes)
		cursor += bytes
	end

	table.move(taken, 1, count, held + 1, entries)

	return cursor
end

return Dictionary
