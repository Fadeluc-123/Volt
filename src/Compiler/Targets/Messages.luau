--[[
    The walk of one event through the emitter for one side: a writer
    with the id first and the mark last for an unreliable event, and an
    outgoing row, when the side fires it; a reader ending in the runtime's
    deliver, and a message row, when it hears it; and the Luau types the
    signatures name
--]]

--!strict
local Messages = {} :: any

local Blocks = require("../Blocks")
local Contract = require("../Config/Contract")
local Emit = require("../Emit")
local Roblox = require("../Config/Roblox")
local Schema = require("../Config/Types/Schema")
local Sizes = require("../Analyse/Sizes")

type Block = Blocks.Block
type Event = Schema.Event
type Field = Schema.Field
type Type = Schema.Type

-- What an event's API entry is built from once it is walked: its id on this side, its writer's signature and its listener's
export type Walked = {
	id: number?,
	label: string,
	typed: string,
	arguments: string,
	listener: string,
	iterator: string,
}

--[[
    The Luau type a value of a schema type is annotated as where one name
    says it
--]]

function Messages.luauType(node: Type): string
	local shape: any = Sizes.resolved(node)
	if shape.kind == "primitive" then
		local name: string = shape.name
		local direct: boolean = name == "boolean" or name == "string" or name == "buffer"

		return direct and name or name == "unknown" and "any" or "number"
	elseif shape.kind == "roblox" then
		return shape.name == "Enum" and `Enum.{shape.item}` or shape.class or Roblox[shape.name].class
	elseif shape.kind == "optional" then
		return `{Messages.luauType(shape.inner)}?`
	end

	-- Whiteoak TODO: any for a struct, list, enum or union until the types module names them
	return "any"
end

-- The fields a fire takes: a pack's parameters, or the one value
function Messages.parameters(event: Event): { Field }
	local data = event.data
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
	local typed: { string }, types: { string } = {}, {}

	write.allocate = reliable and "allocateReliable" or "allocateUnreliable"
	write.slot = reliable and "slotReliable" or "slotUnreliable"

	if outId then
		write:line(`buffer.writeu{width * 8}({write.out}, {write:at(write:reserve(width))}, {outId})`)
	end

	if event.data then
		names, values = self._emitter:block(event.data, write, read)
	end

	for index: number, field: Field in Messages.parameters(event) do
		types[index] = Messages.luauType(field.type)
		typed[index] = `{names[index]}: {types[index]}`
	end

	if outId then
		local size: Sizes.Size = event.data and Sizes.size(event.data) or Sizes.fixed(0)
		local least: number, most: number = Sizes.block(size)

		if not reliable then
			write:tail("markUnreliable()")
		end

		table.insert(self._functions, `local function write{label}({table.concat(typed, ", ")})\n{write:done()}end\n`)
		self._outgoing[outId] =
			`\{ name = "{path}", reliable = {reliable}, minBytes = {width + least}, maxBytes = {width + most} }`
	end

	if inId then
		local delivered: string = #values == 0 and "" or `, {table.concat(values, ", ")}`
		local body: string = read:done(`return runtime:deliver({inId}, player, cursor, sideCursor{delivered})`)
		local rate: string = server and typeof(event.rate) == "number" and `, rate = {event.rate}` or ""
		local taken: string = Emit.parameters(body, Contract.message)

		table.insert(self._functions, `local function read{label}({taken}): (number, number)\n{body}end\n`)
		self._messages[inId] =
			`\{ name = "{path}", kind = "event", mode = "{event.call}", queue = {event.queue}{rate}, read = read{label} }`
	end

	-- A server listener and a server iterator take the player before the values
	local heard: { string } = table.clone(typed)
	local yielded: { string } = table.clone(types)

	if server then
		table.insert(heard, 1, "player: Player")
		table.insert(yielded, 1, "Player")
	end

	table.insert(yielded, 1, "number")

	return {
		id = inId,
		label = label,
		typed = table.concat(typed, ", "),
		arguments = table.concat(names, ", "),
		listener = `({table.concat(heard, ", ")}) -> ()`,
		iterator = `() -> ({table.concat(yielded, ", ")})`,
	}
end

return Messages
