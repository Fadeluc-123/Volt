--[[
    The answering side, merged onto the runtime: the one handler each
    function has on the side its calls reach, the thread a call runs on,
    and the reply or the refusal its result becomes, written back to the
    caller, the server's handler hearing the player first
--]]

--!strict
local Handlers = {}

local Config = require("./Config/Runtime")
local Types = require("./Config/Types/Runtime")

type Limit = Types.Limit
type Message = Types.Message
type Runtime = Types.Runtime

local MESSAGE_BYTES: number = Config.messageBytes
local PREFIX_BYTES: number = Config.prefixBytes
local STATUS = Config.status
local POSITION: string = Config.position

--[[
    Connects the one handler a function has, whose returns become the
    reply, and returns the closure that disconnects it. A second while
    one is connected is an error rather than a silent replacement
--]]

function Handlers.handle(self: Runtime, id: number, handler: (...any) -> ...any): () -> ()
	local handlers = self._handlers

	assert(handlers[id] == nil, `{self._messages[id].name}: a handler is already connected`)
	handlers[id] = handler

	-- Cleanup and disconnect from handler
	return function ()
		if handlers[id] == handler then
			handlers[id] = nil
		end
	end
end

-- Whether a function has its handler connected, which a generated module's connected answers with
function Handlers.handled(self: Runtime, id: number): boolean
	return self._handlers[id] ~= nil
end

--[[
    Runs a call: the handler on a thread of its own, since most yield,
    with its returns as the reply; a call past the function's rate,
    answered before it is reported, or with no handler is refused at
    once, and one a hook vetoes is dropped, so its caller waits out the
    timeout, since a veto that must answer is the handler's to make.
    Returns the cursors, so a reader's tail is this one call
--]]

function Handlers.call(
	self: Runtime,
	id: number,
	player: any,
	slot: number,
	cursor: number,
	sideCursor: number,
	...: any
): (number, number)
	local message: Message = self._messages[id]
	local limit: Limit? = self._limits[id]
	local handler = self._handlers[id]

	if limit and not self:allow(player, id, limit) then
		self:_reply(id, player, slot, STATUS.limited, "rate limited")
		self:_limited(player, message.name, limit)
	elseif self._hooked and not self:guard(id, player, ...) then
		return cursor, sideCursor
	elseif handler then
		self._spawn(self._serve, self, id, player, slot, handler, ...)
	else
		self:_reply(id, player, slot, STATUS.unhandled, "no handler")
	end

	return cursor, sideCursor
end

--[[
    Serves one call: the handler's returns become the reply. Its error's
    first line refuses the call, cut of its source position so no script
    path reaches the caller, and then the whole of it, traceback and all,
    is reported. The server's handler hears the player first, and the
    client's the values alone, as a listener does
--]]

function Handlers._serve(self: Runtime, id: number, player: any, slot: number, handler: (...any) -> ...any, ...: any)
	local results: { n: number, [number]: any }

	if self._server then
		results = table.pack(xpcall(handler, self._trace, player, ...))
	else
		results = table.pack(xpcall(handler, self._trace, ...))
	end

	if results[1] then
		return self:_reply(id, player, slot, STATUS.ok, table.unpack(results, 2, results.n))
	end

	local message: string = tostring(results[2])
	local first: string = message:match("^[^\n]*") :: string

	self:_reply(id, player, slot, STATUS.failed, (first:gsub(POSITION, "")))
	self:fail(player, "handler", message, self._messages[id].name)
end

--[[
    Writes a reply into the caller's state: the returns after a status of
    ok, or after any other the reason, cut to what a refusal carries. A
    return the function's return type cannot carry is the handler's
    bug: the writer refuses it and undoes the reply, which then fails
    the call with the refusal before the failure is reported, named for
    the function. Nothing is sent to a player who has left
--]]

function Handlers._reply(self: Runtime, id: number, player: any, slot: number, status: number, ...: any)
	-- The client's one caller is the server, whose state its reliable send always points at
	if self._server and not self:target(player) then
		return
	end

	local message: Message = self._messages[id]
	local reply = message.reply :: (slot: number, status: number, ...any) -> ()

	if status == STATUS.ok then
		local ok: boolean, refused: any = pcall(reply, slot, status, ...)
		if ok then
			return
		end

		local reason: string = self.reliable:undo(message.name, refused) -- A refusal names the return itself

		self:_reply(id, player, slot, STATUS.failed, reason)
		return self:fail(player, "handler", reason, message.name)
	end

	local reason: string = ...
	reason = reason:sub(1, MESSAGE_BYTES)
	reply(slot, status)

	local offset: number, out: buffer = self.reliable.allocate(PREFIX_BYTES + #reason)
	buffer.writeu16(out, offset, #reason)
	buffer.writestring(out, offset + PREFIX_BYTES, reason)
end

return Handlers
