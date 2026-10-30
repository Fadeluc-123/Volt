--[[
    The baselines of @delta events, merged onto the runtime: on the
    server, a copy per player of the value each such event last wrote
    them, so a fire writes only the fields that changed; on the client,
    the value last delivered, which fills in the fields a message leaves out
--]]

--!strict
local Delta = {}

local Types = require("./Config/Types/Runtime")

type Hook = Types.Hook
type Joined = Types.Joined
type Message = Types.Message
type Outgoing = Types.Outgoing
type Runtime = Types.Runtime
type Send = Types.Send

type Value = { [string]: any }
type Write = (mask: number, value: any) -> ()

-- Whether two values are the same: tables walked by key, buffers by content and everything else by ==
local function same(a: any, b: any): boolean
	if a == b then
		return true
	end

	local kind: string = type(a)
	if kind ~= type(b) then
		return false
	end

	if kind == "buffer" then
		return buffer.len(a) == buffer.len(b) and buffer.tostring(a) == buffer.tostring(b)
	end

	if kind ~= "table" then
		return false
	end

	for key: any, inner: any in a do
		if not same(inner, b[key]) then
			return false
		end
	end

	-- Every key of the first is in the second with the same value, so only a key the first lacks is left to differ
	for key: any in b do
		if a[key] == nil then
			return false
		end
	end

	return true
end

-- A value of its own, its tables and buffers copied all the way down, so a game editing its value in place is seen
local function copy(value: any): any
	local kind: string = type(value)

	if kind == "buffer" then
		local copied: buffer = buffer.create(buffer.len(value))
		buffer.copy(copied, 0, value)
		return copied
	end

	if kind ~= "table" then
		return value
	end

	local copied: { [any]: any } = {}

	for key: any, inner: any in value do
		copied[key] = copy(inner)
	end

	return copied
end

-- Whiteoak TODO: Only top-level fields are masked, so a nested struct, array or map that changes anywhere goes whole

-- The fields a value changes against a baseline, as a mask; every field with no baseline, or no table to compare
local function masked(fields: { string }, value: any, baseline: Value?): number
	if not baseline or type(value) ~= "table" then
		return 2 ^ #fields - 1
	end

	local mask: number = 0

	for index: number, field: string in fields do
		if not same(value[field], baseline[field]) then
			mask += 2 ^ (index - 1)
		end
	end

	return mask
end

-- Writes the value under a mask, through the runtime's write when the module's writers do not check their values
local function put(self: Runtime, id: number, write: Write, mask: number, value: any)
	if self._checked then
		write(mask, value)
	else
		self:write(id, write, mask, value)
	end
end

-- Keeps what a player was just written through an event as their baseline of it
local function keep(joined: Joined, id: number, baseline: any)
	local sent: { [number]: any } = joined.sent or {}

	sent[id] = baseline
	joined.sent = sent
end

--[[
    Every fire variant of a @delta event: asks the hook before the send,
    works out each recipient's mask from the value last written them, and
    writes the value once per distinct mask, into the one player's own
    state, or into the scratch state copied to that mask's recipients,
    with their baselines set to one copy of it before the copies are made
--]]

-- Whiteoak TODO: A fire deep-copies its value once and deep-compares it once per distinct baseline; dirty marks the
-- game hands in would skip both

function Delta.delta(
	self: Runtime,
	id: number,
	player: any,
	targets: { [any]: any }?,
	except: any?,
	write: Write,
	value: any
)
	local hook: Hook? = self.before[id]
	if hook and not hook(player or targets, value) then
		return
	end

	local row: Outgoing = self._outgoing[id]
	local stream: number? = row.stream
	local send: Send = stream and self.streams[stream] or self.reliable -- An event on a channel rides its send
	local fields: { string } = row.fields :: { string }
	local players: { [any]: Joined } = self._players

	if player ~= nil then
		if not self:target(player, stream) then
			return
		end

		-- A message that already took their frame past the cap goes first, and clears the baseline this would patch
		send:drop()

		-- A handler told of that drop may have let them go
		local joined: Joined? = players[player]
		if not joined then
			return
		end

		local sent: { [number]: any }? = joined.sent

		put(self, id, write, masked(fields, value, sent and sent[id]), value)
		keep(joined, id, copy(value))

		return
	end

	self:_setUp(targets)

	-- Those listed or set, or everyone set up but one, never one whose handshake failed
	local reached: { any } = {}

	if targets then
		for key: any, entry: any in targets do
			local target: any = typeof(key) == "number" and entry or key
			local joined: Joined? = players[target]

			if joined and not joined.reliable.refused then
				table.insert(reached, target)
			end
		end
	else
		for target: any, joined: Joined in players do
			if target ~= except and not joined.reliable.refused then
				table.insert(reached, target)
			end
		end
	end

	-- What already took a frame past the cap goes first, as for one player, and before any mask is worked out
	for _, target: any in reached do
		local joined: Joined? = players[target]

		if joined then
			send.current = stream and joined.streams[stream] or joined.reliable
			send:drop()
		end
	end

	-- Recipients sharing a baseline are compared once, and those sharing a mask are written to once
	local compared: { [any]: number } = {}
	local masks: { [number]: { any } } = {}

	for _, target: any in reached do
		local joined: Joined? = players[target]
		local sent: { [number]: any }? = joined and joined.sent
		local baseline: Value? = sent and sent[id]

		if joined then
			local mask: number = compared[baseline] or masked(fields, value, baseline)
			local list: { any }? = masks[mask]

			if baseline then
				compared[baseline] = mask
			end

			if list then
				table.insert(list, target)
			else
				masks[mask] = { target }
			end
		end
	end

	local kept: any = nil -- The one copy every recipient keeps, made once the first write has succeeded

	for mask: number, list: { any } in masks do
		send.current = send.scratch
		put(self, id, write, mask, value)
		kept = kept or copy(value)

		for _, target: any in list do
			local joined: Joined? = players[target]

			if joined then
				keep(joined, id, kept)
			end
		end

		send:broadcast(list)
	end
end

--[[
    The tail of a @delta event's reader, inside its call to deliver: fills
    each field the mask leaves out from the value the event last
    delivered, keeps the result as the next, and returns it frozen. With
    no value to fill from, the server wrote against one this client never had
--]]

function Delta.merge(self: Runtime, id: number, mask: number, partial: Value): Value
	local message: Message = self._messages[id]
	local fields: { string } = message.fields :: { string }
	local last: Value? = self._baselines[id]

	if mask ~= 2 ^ #fields - 1 then
		if not last then
			error(`{message.name}: no baseline`, 0)
		end

		for index: number, field: string in fields do
			if not bit32.btest(mask, 2 ^ (index - 1)) then
				partial[field] = last[field]
			end
		end
	end

	local value: Value = table.freeze(partial)
	self._baselines[id] = value

	return value
end

-- Clears every baseline a player has, so the next fire of each @delta event to them is whole whatever was lost
function Delta._forget(self: Runtime, player: any)
	local joined: Joined? = self._players[player]

	if joined then
		joined.sent = nil
	end
end

return Delta
