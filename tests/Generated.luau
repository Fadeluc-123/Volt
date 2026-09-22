--[[
    The harness the generator tests run generated code through: a schema
    text compiled through every stage before the generator, its events
    rendered as one loadable chunk that is also the emitter's golden, the
    chunk loaded over the calls a writer makes, and an assembled module
    loaded as a game would, over a transport of the test's and with the
    promise stand-in for the promise library
--]]

--!strict
local luau = require("@lune/luau")

local Environment = require("./Environment")
local Promise = require("./Promise")
local Volt = require("@volt")
local Analyse = require("@volt/Compiler/Analyse")
local Blocks = require("@volt/Compiler/Blocks")
local Contract = require("@volt/Compiler/Config/Contract")
local Diagnostics = require("@volt/Compiler/Diagnostics")
local Emit = require("@volt/Compiler/Emit")
local Helpers = require("@volt/Compiler/Emit/Helpers")
local Lexer = require("@volt/Compiler/Lexer")
local Messages = require("@volt/Compiler/Targets/Messages")
local Parser = require("@volt/Compiler/Parser")
local Resolve = require("@volt/Compiler/Resolve")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Source = require("@volt/Compiler/Source")
local Targets = require("@volt/Compiler/Targets")
local Types = require("@volt/Compiler/Targets/Types")

type Block = Blocks.Block
type Diagnostics = Diagnostics.Diagnostics
type Event = Schema.Event
type Field = Schema.Field
type File = Schema.File
type Transport = Volt.Transport

-- The calls a rendered chunk's writers may make, as a module names them and in the order the chunk takes them
local CALLS: { string } = { "beginReliable", "allocateReliable", "slotReliable", "refuseReliable" }

local Generated = {}

--[[
    Runs a schema text through every stage before the generator, refusing
    one that does not compile clean. Returns the file, its hash and the
    diagnostics, which the generator adds its own to
--]]

function Generated.compile(name: string, text: string): (File, number, Diagnostics)
	local diagnostics: Diagnostics = Diagnostics.new(Source.new(`{name}.volt`, text))
	local file: File = Parser.parse(Lexer.scan(diagnostics.source, diagnostics), diagnostics)

	Resolve.file(file, diagnostics)

	local hash: number = Analyse.file(file, diagnostics)
	assert(diagnostics.errors == 0, diagnostics:render())

	return file, hash, diagnostics
end

-- The assembled modules of a schema text: the client's, the server's and the types
function Generated.modules(name: string, text: string): (string, string, string)
	local file: File, hash: number, diagnostics: Diagnostics = Generated.compile(name, text)
	local client: string, server: string, types: string = Targets.modules(file, diagnostics, hash)

	assert(diagnostics.errors == 0, diagnostics:render())

	return client, server, types
end

function Generated.events(file: File): { Event }
	local list: { Event } = {}
	for _, declaration in file.declarations do
		if declaration.kind == "event" then
			table.insert(list, declaration)
		end
	end
	return list
end

--[[
    Renders every event of a file as a write function over the calls a
    writer makes and a read function over a bare buffer and side array,
    with the named types, helpers, constants and shared pairs they need
    above them and a table of the pairs at the end, so the text is one
    loadable chunk and one golden file
--]]

function Generated.render(file: File): string
	local emitter = Emit.new(file.options)
	local parts: { string } = {}
	local exports: { string } = {}
	local functions: { string } = {}
	local named: { string } = Types.named(file.declarations, {})

	-- An exported type has its pair whether or not a message refers to it
	for _, declaration in file.declarations do
		if declaration.kind == "type" and declaration.export then
			emitter:shared(declaration)
		end
	end

	for _, event: Event in Generated.events(file) do
		local write: Block = Blocks.new("write", event.name)
		local read: Block = Blocks.new("read", event.name)
		local names: { string }, values: { string } = {}, {}

		-- A message writes through the chunk's own calls, named as a module names them
		write.first = "beginReliable"
		write.allocate = "allocateReliable"
		write.slot = "slotReliable"
		write.refuse = "refuseReliable"

		if event.data then
			names, values = emitter:block(event.data, write, read)
		end

		local typed: { string } = {}
		for index: number, field: Field in Messages.parameters(event.data) do
			typed[index] = `{names[index]}: {Types.annotation(field.type)}`
		end

		local results: string = #values == 0 and "" or `, {table.concat(values, ", ")}`
		local body: string = read:done(`return cursor, sideCursor{results}`)
		local taken: string = Emit.parameters(body, Contract.read)

		table.insert(functions, `local function write{event.name}({table.concat(typed, ", ")})\n{write:done()}end\n`)
		table.insert(functions, `local function read{event.name}({taken})\n{body}end\n`)
		table.insert(exports, `\t{event.name} = \{ write = write{event.name}, read = read{event.name} },`)
	end

	local helpers: { string } = {}
	for name: string in emitter.helpers do
		table.insert(helpers, name)
	end

	table.sort(helpers)

	-- The chunk takes only the calls its writers make, in the order load hands them
	local body: string = table.concat(functions, "")
	local taken: { string } = {}

	for _, name: string in CALLS do
		if body:find(name, 1, true) then
			table.insert(taken, name)
		end
	end

	table.insert(parts, `local {table.concat(taken, ", ")} = ...\n`)

	if #named > 0 then
		table.insert(parts, `{table.concat(named, "\n")}\n`)
	end

	for _, name: string in helpers do
		table.insert(parts, Helpers[name])
	end
	for _, constant: string in emitter.constants do
		table.insert(parts, `{constant}\n`)
	end

	table.move(emitter.functions, 1, #emitter.functions, #parts + 1, parts)
	table.move(functions, 1, #functions, #parts + 1, parts)
	table.insert(parts, `return \{\n{table.concat(exports, "\n")}\n}\n`)

	return table.concat(parts, "\n")
end

--[[
    Loads a rendered chunk with the calls a writer makes: an allocator
    that grows a buffer as the writers ask, a begin that records where a
    message starts, a slot store filling a side array and a refuse that
    returns to the start before it raises, as the runtime's do; and a
    packet function that hands back exactly what was written since the
    last call
--]]

function Generated.load(name: string, text: string): (any, () -> (buffer, { any }))
	local out: buffer = buffer.create(64)
	local cursor: number = 0
	local side: { any } = {}
	local sideCursor: number = 1
	local committed: number, sideCommitted: number = 0, 1 -- Where the message being written began

	local function allocate(bytes: number): (number, buffer)
		if cursor + bytes > buffer.len(out) then
			local grown: buffer = buffer.create(math.max(buffer.len(out) * 2, cursor + bytes))
			buffer.copy(grown, 0, out, 0, cursor)
			out = grown
		end

		local offset: number = cursor
		cursor += bytes

		return offset, out
	end

	local function begin(bytes: number): (number, buffer)
		committed, sideCommitted = cursor, sideCursor
		return allocate(bytes)
	end

	local function slot(value: any)
		side[sideCursor] = value
		sideCursor += 1
	end

	local function refuse(message: string)
		cursor, sideCursor = committed, sideCommitted
		error(message, 0)
	end

	local function packet(): (buffer, { any })
		local exact: buffer = buffer.create(cursor)
		local slots: { any } = table.move(side, 1, sideCursor - 1, 1, {})

		buffer.copy(exact, 0, out, 0, cursor)
		cursor = 0
		side = {}
		sideCursor = 1

		return exact, slots
	end

	-- The chunk's first line names the calls it takes, so it is given those and no other
	local given: { any } = {}
	local calls: { [string]: any } = {
		beginReliable = begin,
		allocateReliable = allocate,
		slotReliable = slot,
		refuseReliable = refuse,
	}

	for taken: string in (text:match("^local (.-) = %.%.%.") :: string):gmatch("[%w_]+") do
		table.insert(given, calls[taken])
	end

	local chunk = luau.load(text, { debugName = name, environment = Environment })
	return chunk(table.unpack(given)), packet
end

-- A path under a service, growing by one name per index, so require can tell one library's from another's
local function path(text: string): any
	return setmetatable({}, {
		__index = function (_, key: string)
			return path(`{text}.{key}`)
		end,

		__tostring = function ()
			return text
		end,
	})
end

--[[
    Loads an assembled module as a game would: game answers GetService
    with a path any runtime path resolves under, and require hands back
    the promise stand-in for the promise library's path and, for any
    other, a Volt whose start takes the transport given here in place of
    the remotes. Returns the module
--]]

function Generated.module(name: string, text: string, transport: Transport): any
	local environment: { [string]: any } = table.clone(Environment)

	environment.game = {
		GetService = function (_, service: string)
			return path(service)
		end,
	}

	environment.require = function (target: any): any
		if tostring(target):match("%.Promise$") then
			return Promise
		end

		return {
			start = function (schema: Volt.Schema)
				return Volt.start(schema, transport)
			end,
		}
	end

	local chunk = luau.load(text, { debugName = name, environment = environment })
	return chunk()
end

return Generated
