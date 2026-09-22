--[[
    The walk of one message through the emitter for one side: an event's
    writer, id first and mark last when unreliable, and its reader ending
    in deliver; a function's call and reply, written and read from the
    side that sends each; the schema rows of both, and the Luau types
--]]

--!strict
local Messages = {} :: any

local Blocks = require("../Blocks")
local Contract = require("../Config/Contract")
local Emit = require("../Emit")
local Schema = require("../Config/Types/Schema")
local Sizes = require("../Analyse/Sizes")
local Types = require("./Types")
local Wire = require("../Config/Wire")

type Block = Blocks.Block
type Event = Schema.Event
type Field = Schema.Field
type Function = Schema.Function
type Pack = Schema.Pack
type Type = Schema.Type

-- What an event's API entry is built from once it is walked: its ids on this side, its writer's signature and its listener's
export type Walked = {
	id: number?, -- Heard as
	out: number?, -- Sent as
	label: string,
	typed: string,
	arguments: string,
	listener: string,
	iterator: string,
}

-- What a function's API entry is built from once it is walked: this side's id, the call's signature, what it returns and the handler's
export type Exchanged = {
	id: number,
	label: string,
	typed: string,
	arguments: string,
	result: string, -- What invoke is annotated as returning: the error tuple, or nothing said for a promise
	handler: string,
}

local SLOT_BYTES: number = Wire.slotBytes
local STATUS_BYTES: number = Wire.statusBytes

-- The prefix and the bounds of the reason a refusal carries, by the length rule the runtime follows
local REASON_PREFIX: number, REASON_MIN: number, REASON_MAX: number =
	Sizes.lengths({ min = 0, max = Wire.replyMessage, start = 0, finish = 0 })

-- The bytes a message's payload takes at its least and most, laid out as its block
local function bounds(data: (Type | Pack)?): (number, number)
	return Sizes.block(data and Sizes.size(data) or Sizes.fixed(0))
end

-- The id a writer puts first among its fixed bytes
local function identify(write: Block, width: number, id: number)
	write:line(`buffer.writeu{width * 8}({write.out}, {write:at(write:reserve(width))}, {id})`)
end

-- A fixed field of a call's framing, written from the parameter of that name and read into a local of it
local function frame(write: Block, read: Block, name: string, bytes: number)
	write:line(`buffer.writeu{bytes * 8}({write.out}, {write:at(write:reserve(bytes))}, {name})`)
	read:line(`local {name}: number = buffer.readu{bytes * 8}(packet, {read:at(read:reserve(bytes))})`)
end

-- The values a reader hands on after the cursors, as the tail of an argument list
local function handed(values: { string }): string
	return #values == 0 and "" or `, {table.concat(values, ", ")}`
end

-- Points a message's write block at the runtime's calls for one reliability, the module's locals of that name
local function sends(write: Block, reliable: boolean)
	local suffix: string = reliable and "Reliable" or "Unreliable"

	write.first = `begin{suffix}`
	write.allocate = `allocate{suffix}`
	write.slot = `slot{suffix}`
	write.refuse = `refuse{suffix}`
end

-- Each field of a pack typed under the name the walk gave it, and the types alone
local function typed(names: { string }, data: (Type | Pack)?): ({ string }, { string })
	local annotated: { string }, types: { string } = {}, {}
	for index: number, field: Field in Messages.parameters(data) do
		types[index] = Types.annotation(field.type)
		annotated[index] = `{names[index]}: {types[index]}`
	end
	return annotated, types
end

-- The fields a pack of data carries: a pack's parameters, or the one value
function Messages.parameters(data: (Type | Pack)?): { Field }
	if not data then
		return {}
	elseif data.kind == "pack" then
		return data.parameters
	end

	return { {
		name = "value",
		type = data,
		start = data.start,
		finish = data.finish,
	} }
end

--[[
    Walks one event through the emitter and keeps what this side needs:
    a writer with the id first and, for an unreliable event, the mark
    last, and an outgoing row, when the side fires it; a reader ending in
    the runtime's deliver, and a message row, when it hears it. Both
    blocks are walked either way, since the emitter fills both at once
--]]

function Messages:walk(event: Event, fires: boolean, hears: boolean): Walked
	local server: boolean = self._server
	local path: string = event.path :: string
	local label: string = path:gsub("%.", "_")
	local reliable: boolean = event.type == "Reliable"
	local outId: number? = fires and (server and event.toClient or event.toServer) or nil
	local inId: number? = hears and (server and event.toServer or event.toClient) or nil
	local width: number = Sizes.idBytes(server and self._toClient or self._toServer)
	local write: Block = Blocks.new("write", path)
	local read: Block = Blocks.new("read", path)
	local names: { string }, values: { string } = {}, {}

	sends(write, reliable)

	if outId then
		identify(write, width, outId)
	end

	if event.data then
		names, values = self._emitter:block(event.data, write, read)
	end

	local annotated: { string }, types: { string } = typed(names, event.data)

	if outId then
		local least: number, most: number = bounds(event.data)

		if not reliable then
			write:tail("markUnreliable()")
		end

		table.insert(
			self._functions,
			`local function write{label}({table.concat(annotated, ", ")})\n{write:done()}end\n`
		)
		self._outgoing[outId] =
			`\{ name = "{path}", kind = "event", reliable = {reliable}, minBytes = {width + least}, maxBytes = {width + most} }`
	end

	if inId then
		local body: string = read:done(`return runtime:deliver({inId}, player, cursor, sideCursor{handed(values)})`)
		local rate: string = server and typeof(event.rate) == "number" and `, rate = {event.rate}` or ""
		local taken: string = Emit.parameters(body, Contract.message)

		table.insert(self._functions, `local function read{label}({taken}): (number, number)\n{body}end\n`)
		self._messages[inId] =
			`\{ name = "{path}", kind = "event", mode = "{event.call}", queue = {event.queue}{rate}, read = read{label} }`
	end

	-- A server listener and a server iterator take the player before the values
	local heard: { string } = table.clone(annotated)
	local yielded: { string } = table.clone(types)

	if server then
		table.insert(heard, 1, "player: Player")
		table.insert(yielded, 1, "Player")
	end

	table.insert(yielded, 1, "number")

	return {
		id = inId,
		out = outId,
		label = label,
		typed = table.concat(annotated, ", "),
		arguments = table.concat(names, ", "),
		listener = `({table.concat(heard, ", ")}) -> ()`,
		iterator = `() -> ({table.concat(yielded, ", ")})`,
	}
end

--[[
    Walks one function through the emitter for one side: the call, slot
    first after the id, which the client writes and the server reads into
    the runtime's call; and the reply, whose returns follow the status
    only when it is ok, which the server writes and the client reads into
    the runtime's reply, or its refused. Both are walked on both sides
--]]

function Messages:exchange(declaration: Function): Exchanged
	local server: boolean = self._server
	local path: string = declaration.path :: string
	local label: string = path:gsub("%.", "_")
	local width: number = Sizes.idBytes(server and self._toClient or self._toServer)
	local callId: number = declaration.toServer :: number
	local replyId: number = declaration.toClient :: number
	local returns: (Type | Pack)? = declaration["return"]
	local callWrite: Block, callRead: Block = Blocks.new("write", path), Blocks.new("read", path)
	local replyWrite: Block, replyRead: Block = Blocks.new("write", path), Blocks.new("read", path)
	local names: { string }, values: { string } = {}, {}
	local results: { string }, yields: { string } = {}, {}

	sends(callWrite, true)
	sends(replyWrite, true)

	identify(callWrite, width, callId)
	frame(callWrite, callRead, "slot", SLOT_BYTES)

	if declaration.data then
		names, values = self._emitter:block(declaration.data, callWrite, callRead)
	end

	identify(replyWrite, width, replyId)
	frame(replyWrite, replyRead, "slot", SLOT_BYTES)
	frame(replyWrite, replyRead, "status", STATUS_BYTES)

	-- The returns are a block of their own under the status, since a refusal carries none
	local returnsWrite: Block = replyWrite:child()
	local returnsRead: Block = replyRead:child()

	replyRead:open("if status == 0 then")

	-- The returns are checked on every build, since a return the type cannot carry is the server's own bug
	-- Whiteoak TODO: a shared type first walked here keeps its checks elsewhere in a module with validation off
	local validated: boolean = self._emitter:validating(true)

	if returns then
		results, yields = self._emitter:block(returns, returnsWrite, returnsRead)
	end

	self._emitter:validating(validated)

	if not returnsWrite:empty() then
		replyWrite:open("if status == 0 then")
		returnsWrite:done()
		replyWrite:close("end")
	end

	returnsRead:done(`return runtime:reply({replyId}, slot, cursor, sideCursor{handed(yields)})`)
	replyRead:close("end")

	local annotated: { string } = typed(names, declaration.data)
	local returned: { string }, returnTypes: { string } = typed(results, returns)

	if server then
		local body: string =
			callRead:done(`return runtime:call({callId}, player, slot, cursor, sideCursor{handed(values)})`)
		local taken: string = Emit.parameters(body, Contract.message)
		local rate: string = typeof(declaration.rate) == "number" and `, rate = {declaration.rate}` or ""
		local given: string = table.concat({ "slot: number", "status: number", table.unpack(returned) }, ", ")
		local least: number, most: number = bounds(returns)
		local shortest: number = width + SLOT_BYTES + STATUS_BYTES + math.min(least, REASON_PREFIX + REASON_MIN)
		local longest: number = width + SLOT_BYTES + STATUS_BYTES + math.max(most, REASON_PREFIX + REASON_MAX)

		table.insert(self._functions, `local function read{label}({taken}): (number, number)\n{body}end\n`)
		table.insert(self._functions, `local function write{label}({given})\n{replyWrite:done()}end\n`)
		self._messages[callId] = `\{ name = "{path}", kind = "call"{rate}, read = read{label}, reply = write{label} }`
		self._outgoing[replyId] =
			`\{ name = "{path}", kind = "reply", reliable = true, minBytes = {shortest}, maxBytes = {longest} }`
	else
		local body: string =
			replyRead:done(`return runtime:refused({replyId}, slot, packet, cursor, sideCursor, length)`)
		local taken: string = Emit.parameters(body, Contract.message)
		local promise: string = declaration.yield == "Promise" and ", promise = Promise" or ""
		local given: string = table.concat({ "slot: number", table.unpack(annotated) }, ", ")
		local least: number, most: number = bounds(declaration.data)
		local shortest: number = width + SLOT_BYTES + least
		local longest: number = width + SLOT_BYTES + most

		self._promise = self._promise or promise ~= ""
		table.insert(self._functions, `local function write{label}({given})\n{callWrite:done()}end\n`)
		table.insert(self._functions, `local function read{label}({taken}): (number, number)\n{body}end\n`)
		self._messages[replyId] =
			`\{ name = "{path}", kind = "reply", timeout = {declaration.timeout}{promise}, read = read{label} }`
		self._outgoing[callId] =
			`\{ name = "{path}", kind = "call", reliable = true, minBytes = {shortest}, maxBytes = {longest} }`
	end

	-- A server handler takes the player before the arguments; a call that yields answers with the error tuple
	local heard: { string } = table.clone(annotated)
	local tuple: { string } = { "boolean", table.unpack(returnTypes) }

	table.insert(heard, 1, "player: Player")

	return {
		id = server and callId or replyId,
		label = label,
		typed = table.concat(annotated, ", "),
		arguments = table.concat(names, ", "),
		result = declaration.yield == "Promise" and "" or `: ({table.concat(tuple, ", ")})`,
		handler = `({table.concat(heard, ", ")}) -> ({table.concat(returnTypes, ", ")})`,
	}
end

return Messages
