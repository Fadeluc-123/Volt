--[[
    The fires a generated module makes through the runtime, merged onto
    it: one through its writer under pcall, as a module built without
    write validation fires, and a broadcast written once and copied into
    every target it should reach, each on the stream its message rides
--]]

--!strict
local Fires = {}

local Types = require("./Config/Types/Runtime")

type Hook = Types.Hook
type Outgoing = Types.Outgoing
type Runtime = Types.Runtime
type Send = Types.Send

-- The send a message rides: its channel's, else the default reliable stream or the unreliable one
local function sending(self: Runtime, row: Outgoing): Send
	local stream: number? = row.stream
	if stream then
		return self.streams[stream]
	end

	return row.reliable and self.reliable or self.unreliable
end

--[[
    Fires a message the way a module built without write validation does:
    its writer runs under pcall, so a value that raises part way through,
    in a buffer write or a field of the wrong kind, leaves nothing of its
    message behind and reaches whoever fired named for the message
--]]

function Fires.write(self: Runtime, id: number, write: (...any) -> (), ...: any)
	local ok: boolean, message: any = pcall(write, ...)
	if ok then
		return
	end

	local row: Outgoing = self._outgoing[id]

	error(sending(self, row):undo(row.name, message), 0)
end

--[[
    Writes a message once, to the scratch states, and copies it to every
    target, or to those listed or set, or to all but one, unless the hook
    before its send vetoes it. Every broadcast variant of the generated
    API is this one call with the message's writer and its arguments
--]]

function Fires.broadcast(
	self: Runtime,
	id: number,
	targets: { [any]: any }?,
	except: any?,
	write: (...any) -> (),
	...: any
)
	local hook: Hook? = self.before[id]
	if hook and not hook(targets, ...) then
		return
	end

	self:_setUp(targets)

	local row: Outgoing = self._outgoing[id]
	local send: Send = sending(self, row)

	-- Written once into the scratch states, which the send then copies into every target's
	self.reliable.current = self.reliable.scratch
	self.unreliable.current = self.unreliable.scratch
	send.current = send.scratch

	-- An unchecked writer that raised would leave the scratch state dirty for the next broadcast
	if self._checked then
		write(...)
	else
		self:write(id, write, ...)
	end

	send:broadcast(targets, except, id, row.sequence)
end

return Fires
