--[[
    Assembles the client and server modules from a resolved schema: the
    entry point that refuses a name the API owns, the shell of a module
    (header, requires, send locals and the schema table) and the assembly
    of every piece in reading order. The API tables and the walk of each
    message are the methods of one sibling file each
--]]

--!strict
local Targets = {} :: any
Targets.__index = Targets

-- An init file stands for its folder, so its siblings are reached through the folder's name
local Api = require("./Targets/Api")
local Blocks = require("./Blocks")
local Contract = require("./Config/Contract")
local Diagnostics = require("./Diagnostics")
local Emit = require("./Emit")
local Helpers = require("./Emit/Helpers")
local Messages = require("./Targets/Messages")
local Reserved = require("./Config/Reserved")
local Schema = require("./Config/Types/Schema")
local Sizes = require("./Analyse/Sizes")

type Declaration = Schema.Declaration
type Diagnostics = Diagnostics.Diagnostics
type File = Schema.File
type Parameter = Contract.Parameter

-- A send function of the runtime as a writer names it, and where it is taken from once the runtime exists
type Send = { name: string, type: string, from: string }

local VERSION: string = Contract.version

-- The send functions a writer may name, in the order they are declared; filled from the contract below
local SENDS: { Send } = {}

for _, reliability: string in { "Reliable", "Unreliable" } do
	for _, parameter: Parameter in { Contract.begin, table.unpack(Contract.write) } do
		table.insert(SENDS, {
			name = `{parameter.name}{reliability}`,
			type = parameter.type,
			from = `runtime.{reliability:lower()}.{parameter.name}`,
		})
	end
end

table.insert(SENDS, { name = "markUnreliable", type = "() -> ()", from = "runtime.unreliable.mark" })

-- The rows of a schema table by id, or an empty table when the side has none
local function rows(list: { [number]: string }, count: number): string
	local lines: { string } = {}
	for id: number = 1, count do
		if list[id] then
			table.insert(lines, `\t\t[{id}] = {list[id]},`)
		end
	end
	return #lines == 0 and "{}" or `\{\n{table.concat(lines, "\n")}\n\t}`
end

-- A method name in the casing the schema asks for; the names are written in camel
function Targets.cased(name: string, casing: string): string
	if casing == "pascal" then
		return (name:gsub("^%l", string.upper))
	elseif casing == "snake" then
		return (name:gsub("%u", function (letter: string)
			return `_{letter:lower()}`
		end))
	end
	return name
end

--[[
    Both modules of a file, the client's then the server's. A top-level
    declaration that would take the place of one of the API's own members
    is refused first, in the casing the schema asks for
--]]

function Targets.modules(file: File, diagnostics: Diagnostics, hash: number): (string, string)
	local casing: string = file.options.casing :: string
	local path: string = diagnostics.source.path
	local name: string = path:match("([^/\\]+)$") or path

	for _, declaration: Declaration in file.declarations do
		for _, own: string in Reserved.api do
			if declaration.name == Targets.cased(own, casing) then
				local message: string =
					`"{declaration.name}" is a member of the generated API and cannot be a top-level name`
				diagnostics:error("V4001", message, declaration)
			end
		end
	end

	return Targets.new(file, "client"):render(hash, name), Targets.new(file, "server"):render(hash, name)
end

function Targets.new(file: File, side: string)
	local self = setmetatable({
		_file = file,
		_side = side,
		_server = side == "server",
		_casing = file.options.casing :: string,
		_emitter = Emit.new(file.options),
		_toServer = 0, -- The last id in each direction, functions included, which is what sets how wide ids are
		_toClient = 0,
		_promise = false, -- Whether a function on this side yields a promise, so the module requires the library
		_functions = {} :: { string }, -- A writer per message sent and a reader per message heard, in declaration order
		_messages = {} :: { [number]: string }, -- The schema row of every message heard, by id
		_outgoing = {} :: { [number]: string }, -- The schema row of every message sent, by id
	}, Targets)

	self:count(file.declarations)

	return self
end

--[[
    The module text: the API first, since walking the events is what
    emits the functions and the rows, then every piece in the order the
    file reads
--]]

function Targets:render(hash: number, name: string): string
	local emitter = self._emitter
	local api: string = self:api()
	local body: string = table.concat(self._functions, "\n")
	local declared: { string } = { "local runtime: Volt.Runtime" }
	local assigned: { string } = {}
	local helpers: { string } = {}

	for _, send: Send in SENDS do
		if body:find(send.name, 1, true) then
			table.insert(declared, `local {send.name}: {send.type}`)
			table.insert(assigned, `{send.name} = {send.from}`)
		end
	end

	for helper: string in emitter.helpers do
		table.insert(helpers, helper)
	end

	table.sort(helpers)

	local parts: { string } = { self:header(name), `{table.concat(declared, "\n")}\n` }

	for _, helper: string in helpers do
		table.insert(parts, Helpers[helper])
	end
	for _, constant: string in emitter.constants do
		table.insert(parts, `{constant}\n`)
	end

	table.move(emitter.functions, 1, #emitter.functions, #parts + 1, parts)
	table.move(self._functions, 1, #self._functions, #parts + 1, parts)
	table.insert(parts, self:start(hash))

	if #assigned > 0 then
		table.insert(parts, `{table.concat(assigned, "\n")}\n`)
	end

	table.insert(parts, `local net = table.freeze(\{\n{Blocks.indent(1, api)}\n})\n`)
	table.insert(parts, "return net\n")

	return table.concat(parts, "\n")
end

--[[
    The header naming the schema and the compiler, the directives, the
    services the runtime path and the promise library's start from, the
    runtime require and the promise require when a function yields one
--]]

function Targets:header(name: string): string
	local options: { [string]: any } = self._file.options :: any
	local requires: { string } = { `local Volt = require({options.runtime})` }
	local services: { string } = { options.runtime:match("^[^.]+") or options.runtime }
	local lines: { string } = {
		"--[[",
		`    The {self._side} module Volt {VERSION} generated from {name}: a writer per`,
		"    message this side sends, a reader per message it hears, the schema",
		"    table the runtime starts from and the API a game calls. Generated code:",
		"    change the schema and run volt again rather than editing this file",
		"--]]",
		"",
		"--!strict",
		"--!native",
		"--!optimize 2",
	}

	if self._promise then
		local promise: string = options.promise
		local service: string = promise:match("^[^.]+") or promise

		table.insert(requires, `local Promise = require({promise})`)

		if not table.find(services, service) then
			table.insert(services, service)
			table.sort(services)
		end
	end

	for _, service: string in services do
		table.insert(lines, `local {service} = game:GetService("{service}")`)
	end

	table.insert(lines, "")
	table.move(requires, 1, #requires, #lines + 1, lines)
	table.insert(lines, "")

	return table.concat(lines, "\n")
end

--[[
    The schema table the runtime is started with: what the compiler knows
    and the runtime must not derive, the promise library when a function
    yields one, the messages heard by id with their readers, and the
    messages sent by id for their names and sizes
--]]

function Targets:start(hash: number): string
	local options: { [string]: any } = self._file.options :: any
	local server: boolean = self._server
	local settings: { string } = {}

	for _, key: string in Contract.options do
		table.insert(settings, `\t\t{key} = {tostring(options[key])},`)
	end

	-- The three tables stand apart from each other, as entries of a large table literal do
	local tables: string = Blocks.paragraphs({
		`\toptions = \{\n{table.concat(settings, "\n")}\n\t},`,
		`\tmessages = {rows(self._messages, server and self._toServer or self._toClient)},`,
		`\toutgoing = {rows(self._outgoing, server and self._toClient or self._toServer)},`,
	})

	local lines: { string } = {
		"runtime = Volt.start({",
		`\tversion = "{VERSION}",`,
		`\thash = {string.format("0x%08X", hash)},`,
		`\tscope = "{options.scope}",`,
		`\tside = "{self._side}",`,
		`\tidBytes = {Sizes.idBytes(server and self._toServer or self._toClient)},`,
	}

	if self._promise then
		table.insert(lines, "\tpromise = Promise,")
	end

	table.insert(lines, tables)
	table.insert(lines, "})")
	table.insert(lines, "")

	return table.concat(lines, "\n")
end

function Targets:method(name: string): string
	return Targets.cased(name, self._casing)
end

-- The last id given in each direction, functions included, since a function's ids count towards the width
function Targets:count(declarations: { Declaration })
	for _, declaration: Declaration in declarations do
		if declaration.kind == "namespace" then
			self:count(declaration.declarations)
		elseif declaration.kind ~= "type" then
			self._toServer = math.max(self._toServer, declaration.toServer or 0)
			self._toClient = math.max(self._toClient, declaration.toClient or 0)
		end
	end
end

-- The API tables and the walk of an event are the methods of one sibling each, and a name defined twice is a bug
for _, part in { Api, Messages } do
	for name: string, method in part do
		assert(Targets[name] == nil, `Targets.{name} is defined twice`)
		Targets[name] = method
	end
end

return Targets
