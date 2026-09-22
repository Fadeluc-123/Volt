--[[
    What the wrapper plugs into, merged onto the runtime: the hooks a game
    registers before a message is sent and after one is received, each
    able to veto it, the rate a message allows, changed while the game
    runs, and a value serialised on its own through an exported type's
    pair, for a DataStore or a transport of the game's
--]]

--!strict
local Wrapper = {} :: any

local Types = require("./Config/Types/Runtime")

type Hook = Types.Hook
type Message = Types.Message
type Outgoing = Types.Outgoing

local GLOBAL: number = 0 -- Where the hook over every received message sits: the one id no message has

-- The id of an event, or of a function's call too, among a side's rows by its name
local function find(rows: { [number]: Message | Outgoing }, name: string, calls: boolean): number?
	for id: number, row in rows do
		if row.name == name and (row.kind == "event" or calls and row.kind == "call") then
			return id
		end
	end
	return nil
end

-- A hook as the runtime keeps it: a veto counted for the player it concerns, or for the runtime alone
local function counted(self: any, hook: Hook): Hook
	return function (target: any, ...: any): boolean
		if hook(target, ...) then
			return true
		end

		self:_count(target, "rejected", 1)
		return false
	end
end

--[[
    The hook tables and the functions a game registers through, plain
    functions because the generated API hands them out as values. A slot
    holds one hook: registering again replaces it and nil clears it
--]]

function Wrapper:hooks()
	local before: { [number]: Hook? } = {}
	local after: { [number]: Hook? } = {}

	self.before = before -- By the id of the message sent, as the generated fire reads it
	self._after = after -- By the id of the message heard, with the hook over every message at GLOBAL
	self._hooked = false -- Whether any hook is registered on the receive side, so an unhooked receive asks nothing

	self.beforeSend = function (name: string, hook: Hook?)
		local id: number? = find(self._outgoing, name, false)

		assert(id, `{name}: not an event this side sends`)
		before[id] = hook and counted(self, hook) or nil
	end

	self.afterReceive = function (name: string?, hook: Hook?)
		local id: number = GLOBAL

		if name then
			local found: number? = find(self._messages, name, true)

			assert(found, `{name}: not a message this side hears`)
			id = found
		end

		after[id] = hook and counted(self, hook) or nil
		self._hooked = next(after) ~= nil
	end

	-- The server limits what it hears; the client hears the server alone and limits nothing
	self.rate = function (name: string, perSecond: number, burst: number?)
		if not self._server then
			return
		end

		local id: number? = find(self._messages, name, true)

		assert(id, `{name}: not a message this side hears`)
		self._limits[id] = { rate = perSecond, burst = burst or perSecond }
	end
end

-- Whether the hooks let a received message through: the one over every message first, then the message's own
function Wrapper:guard(id: number, player: any, ...: any): boolean
	local after: { [number]: Hook? } = self._after
	local all: Hook?, own: Hook? = after[GLOBAL], after[id]

	return (all == nil or all(player, ...)) and (own == nil or own(player, ...))
end

--[[
    A value serialised on its own through an exported type's writer, as
    one exact buffer with its side array when it carried an instance:
    written to the scratch state, which is empty again after, with the
    current target kept, since on the client that is the server
--]]

function Wrapper:encode(write: (...any) -> (), value: any): (buffer, { any }?)
	local send = self.reliable
	local was = send.current

	send.current = send.scratch

	local ok: boolean, refused: any = pcall(write, send.allocate, send.slot, send.refuse, value)
	send.current = was

	if not ok then
		error(refused, 0)
	end

	return send:take()
end

-- A value read back through an exported type's reader from a buffer and the side array it was encoded with
function Wrapper:decode(read: (...any) -> (number, number, any), packet: buffer, side: { any }?): any
	return select(3, read(packet, 0, side or {}, 1, buffer.len(packet)))
end

return Wrapper
