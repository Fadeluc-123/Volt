--[[
    What the wrapper plugs into, merged onto the runtime: the hooks a game
    registers before a message is sent and after one is received, each
    able to veto it, the rate a message allows, changed while the game
    runs, and a value serialised on its own through an exported type's
    pair, for a DataStore or a transport of the game's
--]]

--!strict
local Wrapper = {}

local Types = require("./Config/Types/Runtime")

type Hook = Types.Hook
type Message = Types.Message
type Outgoing = Types.Outgoing
type Runtime = Types.Runtime

type Rows = { [number]: Message | Outgoing } -- A side's incoming or outgoing rows, cast to this at each find

local GLOBAL: number = 0 -- Where the hook over every received message sits: the one id no message has

-- The id of an event, or of a function's call too, among a side's rows by its name
local function find(rows: Rows, name: string, calls: boolean): number?
	for id: number, row in rows do
		if row.name == name and (row.kind == "event" or calls and row.kind == "call") then
			return id
		end
	end
	return nil
end

-- A hook as the runtime keeps it: a veto counted for the player it concerns, or for the runtime alone
local function counted(self: Runtime, hook: Hook): Hook
	return function (target: any, ...: any): boolean
		if hook(target, ...) then
			return true
		end

		self:_count(target, "rejected", 1)
		return false
	end
end

--[[
    Registers the hook before an event this side sends, which the runtime's
    beforeSend hands a game as a plain function. A slot holds one hook:
    registering again replaces it and nil clears it
--]]

function Wrapper._beforeSend(self: Runtime, name: string, hook: Hook?)
	local calls: boolean = false -- Only an event takes a hook before its send, never a call or a reply
	local id: number? = find(self._outgoing :: Rows, name, calls)

	assert(id, `{name}: not an event this side sends`)
	self.before[id] = hook and counted(self, hook) or nil
end

-- Registers the hook after a message this side hears, or over every message with no name, as afterReceive does
function Wrapper._afterReceive(self: Runtime, name: string?, hook: Hook?)
	local after: { [number]: Hook? } = self._after
	local id: number = GLOBAL

	if name then
		local calls: boolean = true -- What a side hears may be a function's call as well as an event
		local found: number? = find(self._messages :: Rows, name, calls)

		assert(found, `{name}: not a message this side hears`)
		id = found
	end

	after[id] = hook and counted(self, hook) or nil
	self._hooked = next(after) ~= nil
end

-- Changes the rate a message allows; the server limits what it hears, and the client hears the server alone
function Wrapper._rate(self: Runtime, name: string, perSecond: number, burst: number?)
	if not self._server then
		return
	end

	local calls: boolean = true -- A function's call is limited as an event is
	local id: number? = find(self._messages :: Rows, name, calls)

	assert(id, `{name}: not a message this side hears`)
	self._limits[id] = { rate = perSecond, burst = burst or perSecond }
end

-- Whether the hooks let a received message through: the one over every message first, then the message's own
function Wrapper.guard(self: Runtime, id: number, player: any, ...: any): boolean
	local after: { [number]: Hook? } = self._after
	local all: Hook?, own: Hook? = after[GLOBAL], after[id]

	return (all == nil or all(player, ...)) and (own == nil or own(player, ...))
end

--[[
    A value serialised on its own through an exported type's writer, as
    one exact buffer with its side array when it carried an instance:
    written to the scratch state, which is empty again after, whether it
    was written or raised, with the current target kept, since on the
    client that is the server
--]]

function Wrapper.encode(self: Runtime, name: string, write: (...any) -> (), value: any): (buffer, { any }?)
	local send = self.reliable
	local was = send.current

	send.current = send.scratch

	local ok: boolean, refused: any = pcall(write, send.allocate, send.slot, send.refuse, value)
	if not ok then
		local reason: string = send:undo(name, refused)
		send.current = was
		error(reason, 0)
	end

	send.current = was

	return send:take()
end

-- A value read back through an exported type's reader from a buffer and the side array it was encoded with
function Wrapper.decode(_: Runtime, read: (...any) -> (number, number, any), packet: buffer, side: { any }?): any
	return select(3, read(packet, 0, side or {}, 1, buffer.len(packet)))
end

return Wrapper
