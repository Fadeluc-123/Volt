--[[
    Assembles the client, server and types modules from a resolved schema:
    the entry point that refuses a name the API owns, the shell of a
    module (header, requires, types, send locals and the schema table) and
    the assembly of every piece in reading order. The API tables, the walk
    of each message and a side's shards are the methods of a sibling each
--]]

--!strict
local Targets = {}
Targets.__index = Targets

-- An init file stands for its folder, so its siblings are reached through the folder's name
local Api = require("./Targets/Api")
local Blocks = require("./Blocks")
local Contract = require("./Config/Contract")
local Diagnostics = require("./Diagnostics")
local Emit = require("./Emit")
local Inspector = require("./Targets/Inspector")
local Messages = require("./Targets/Messages")
local Output = require("./Config/Output")
local Pieces = require("./Targets/Pieces")
local Reserved = require("./Config/Reserved")
local Roblox = require("./Config/Roblox")
local Schema = require("./Config/Types/Schema")
local Shards = require("./Targets/Shards")
local Sizes = require("./Analyse/Sizes")
local TargetsTypes = require("./Config/Types/Targets")
local Types = require("./Targets/Types")

type Declaration = Schema.Declaration
type Diagnostics = Diagnostics.Diagnostics
type Emit = TargetsTypes.Emit
type Extra = TargetsTypes.Extra
type Fields = TargetsTypes.Fields
type File = Schema.File
type Pack = Schema.Pack
type Self = TargetsTypes.Targets
type Send = Pieces.Send
type Type = Schema.Type

local VERSION: string = Contract.version
local FILE_LOCALS: number = Output.fileLocals
local BOT: string = "type Bot = Volt.Bot" -- A bot is the runtime's type, which every player in a signature may be
local HANDSHAKE: string = "Volt" -- What a handshake failure's detail opens with, as a message's name opens its own

--[[
    The three modules of a file, the client's, the server's and the types,
    then the shards of a side too big for one file and the inspector when
    the schema asks for one. A top-level declaration that would take the
    place of one of the API's own members is refused first, in the casing
    the schema asks for, so is one named like a handshake failure's
    prefix, and so is a top-level type named like one the modules declare
    or name, or like a Roblox type, and a type parameter named so or like
    a named type's label
--]]

function Targets.modules(file: File, diagnostics: Diagnostics, hash: number): (string, string, string, { Extra })
	local casing: string = file.options.casing :: string
	local path: string = diagnostics.source.path
	local name: string = path:match("([^/\\]+)$") or path

	for _, declaration: Declaration in file.declarations do
		for _, own: string in Reserved.api do
			if declaration.name == Types.cased(own, casing) then
				local message: string =
					`"{declaration.name}" is a member of the generated API and cannot be a top-level name`
				diagnostics:error("V4001", message, declaration)
			end
		end

		-- Refused whatever the casing, since a handshake failure's detail would read as this message's own
		if declaration.name == HANDSHAKE then
			local message: string = `"{HANDSHAKE}" opens a handshake failure's detail and cannot be a top-level name`
			diagnostics:error("V4001", message, declaration)
		end

		if declaration.kind == "type" and table.find(Reserved.types, declaration.name) then
			local message: string =
				`"{declaration.name}" is a type the generated modules declare or name and cannot name a type`
			diagnostics:error("V4002", message, declaration)
		elseif declaration.kind == "type" and Roblox[declaration.name] then
			-- The parser reads the name as the Roblox type, so no reference could reach this one
			local message: string =
				`"{declaration.name}" is a Roblox type the schema language names and cannot name a type`
			diagnostics:error("V4002", message, declaration)
		end
	end

	Types.parameters(file.declarations, diagnostics)

	local client: string, extra: { Extra } = Targets.new(file, "client"):render(hash, name, diagnostics)
	local server: string, shards: { Extra } = Targets.new(file, "server"):render(hash, name, diagnostics)

	table.move(shards, 1, #shards, #extra + 1, extra)

	-- Both sides walked again, unlabelled, through the one emitter of the inspector's own that they share
	if file.options.inspectorOutput then
		local walk: Self = Targets.new(file, "server", Inspector.emitter(file.options))
		table.insert(extra, Inspector.module(walk, Targets.new(file, "client", walk._emitter), name, diagnostics))
	end

	return client, server, Types.module(file, name), extra
end

function Targets.new(file: File, side: string, emitter: Emit?): Self
	local fields: Fields = {
		_file = file,
		_side = side,
		_server = side == "server",
		_casing = file.options.casing :: string,
		_emitter = emitter or Emit.new(file.options), -- Given, it is the one an inspector's two walks share
		_label = not emitter and file.options.profileLabels and `Volt {file.options.scope}` or nil, -- Opens every label
		_toServer = 0, -- The last id in each direction, functions included, which is what sets how wide ids are
		_toClient = 0,
		_promise = false, -- Whether a function this side calls yields a promise, so the module requires the library
		_reversed = Types.reversed(file.declarations), -- Whether the schema declares a from: Server function
		_ordered = false, -- Whether the schema declares an ordered event, whose writers take a sequence
		_dictionary = false, -- Whether the schema declares a @dictionary type, whose strings the runtime keeps
		_streams = {} :: { string }, -- Each channel's path, by its number
		_sends = {} :: { Send }, -- The send functions this module's writers may name, filled once the schema is counted
		_reserve = {} :: { string }, -- The schema's own send locals, which no writer's field or parameter may shadow
		_functions = {} :: { string }, -- A writer per message sent and a reader per message heard, in declaration order
		_messages = {} :: { [number]: string }, -- The schema row of every message heard, by id
		_outgoing = {} :: { [number]: string }, -- The schema row of every message sent, by id
		_registry = { events = {}, functions = {}, exports = {} } :: { [string]: { string } }, -- Every entry's full name, by kind
		_entries = {} :: { TargetsTypes.Entry }, -- Every API entry as its walk left it, in declaration order
	}

	local self: Self = setmetatable(fields, Targets) :: any
	self:count(file.declarations)
	self:mark(file.declarations)
	self._sends, self._reserve = Pieces.sends(self._streams, self._ordered)

	return self
end

--[[
    The module text: the API first, since walking the events is what
    emits the functions and the rows, then every piece in the order the
    file reads, the helpers, constants and shared halves only when a kept
    function names them. A side whose one file would declare more locals
    than FILE_LOCALS, or hold more entries than shardSize, is written as an
    entry and its shards instead, which come back beside it
--]]

function Targets.render(self: Self, hash: number, name: string, diagnostics: Diagnostics): (string, { Extra })
	local api: string = self:api()
	local registry: string = self:registry()
	local body: string = table.concat(self._functions, "\n")
	local declared: { string } = { "local runtime: Volt.Runtime" }
	local assigned: { string } = {}
	local pieces: { string } = Pieces.list(self._emitter)
	local needed: { string }, sends: { Send } = Pieces.needed(pieces, self._sends, `{body}\n{api}`)

	for _, send: Send in sends do
		table.insert(declared, `local {send.name}: {send.type}`)
		table.insert(assigned, `{send.name} = {send.from}`)
	end

	local about: string = table.concat({
		`    The {self._side} module Volt {VERSION} generated from {name}: a writer per`,
		"    message this side sends, a reader per message it hears, the schema",
		"    table the runtime starts from and the API a game calls. Generated code:",
		"    change the schema and run volt again rather than editing this file",
	}, "\n")
	local parts: { string } = { self:header(about, self._promise) }
	local aliases: { string } = self:aliases(false)

	table.move(aliases, 1, #aliases, #parts + 1, parts)
	table.insert(parts, `{table.concat(declared, "\n")}\n`)
	table.move(needed, 1, #needed, #parts + 1, parts)
	table.move(self._functions, 1, #self._functions, #parts + 1, parts)
	table.insert(parts, self:start(hash))

	if #assigned > 0 then
		table.insert(parts, `{table.concat(assigned, "\n")}\n`)
	end

	-- The hooks before a send are read by the fires alone, which are built below, so the table is taken here
	if api:find("before[", 1, true) then
		table.insert(parts, "local before: { [number]: Volt.Hook } = runtime.before\n")
	end

	table.insert(parts, `local Network = \{\n{Blocks.indent(1, api)}\n}\n`)
	table.insert(parts, `{registry}\n`)
	table.insert(parts, "return table.freeze(Network)\n")

	local text: string = table.concat(parts, "\n")
	local size: number? = self._file.options.shardSize

	if (size and #self._entries > size) or Pieces.declared(text) > FILE_LOCALS then
		return self:sharded(hash, name, pieces, diagnostics)
	end

	return text, {}
end

--[[
    The header saying what the file is, the directives, the services the
    runtime path and the promise library's start from, the runtime require
    and the promise require when the file needs one
--]]

function Targets.header(self: Self, about: string, promised: boolean): string
	local options: { [string]: any } = self._file.options :: any
	local requires: { string } = { `local Volt = require({options.runtime})` }
	local services: { string } = { options.runtime:match("^[^.]+") or options.runtime }
	local lines: { string } = {
		"--[[",
		about,
		"--]]",
		"",
		"--!strict",
		"--!native",
		"--!optimize 2",
	}

	if promised then
		local promise: string = options.promise
		local service: string = promise:match("^[^.]+") or promise

		table.insert(requires, `local Promise: any = require({promise})`)

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
    The type lines a file spells out, one part each: every named type, the
    bot and this side's handle types. A module exports the named types but
    a private one, and the handles unless a types module does; a shard's
    are all local, since its types are its own
--]]

function Targets.aliases(self: Self, shard: boolean): { string }
	local named: { string } = Types.named(self._file.declarations, {})
	local exported: boolean = not shard and not self._file.options.typesOutput
	local parts: { string } = {}

	for index: number, line: string in named do
		named[index] = shard and (line:gsub("^export ", "")) or line
	end

	if #named > 0 then
		table.insert(parts, `{table.concat(named, "\n")}\n`)
	end

	table.insert(parts, `{BOT}\n`)

	for _, handle: string in Types.handles(self._side, self._casing, exported, self._reversed) do
		table.insert(parts, `{handle}\n`)
	end

	return parts
end

--[[
    The schema table the runtime is started with: what the compiler knows
    and the runtime must not derive, the stamp, each channel's label and
    the dictionary message's id width when the schema has them, the
    promise library when a function yields one, the profiler when the
    module labels, the messages heard by id with their readers, and the
    messages sent by id for their names, sizes and sends
--]]

function Targets.start(self: Self, hash: number): string
	local options: { [string]: any } = self._file.options :: any
	local server: boolean = self._server
	local settings: { string } = {}
	local labels: { string } = {}

	for _, key: string in Contract.options do
		if options[key] ~= nil then
			table.insert(settings, `\t\t{key} = {tostring(options[key])},`)
		end
	end

	for _, path: string in self._streams do
		table.insert(labels, `"{(path:gsub("%.", "_"))}"`)
	end

	-- The three tables stand apart from each other, as entries of a large table literal do
	local tables: string = Blocks.paragraphs({
		`\toptions = \{\n{table.concat(settings, "\n")}\n\t},`,
		`\tmessages = {Pieces.rows(self._messages, server and self._toServer or self._toClient)},`,
		`\toutgoing = {Pieces.rows(self._outgoing, server and self._toClient or self._toServer)},`,
	})

	local lines: { string } = {
		"runtime = Volt.start({",
		`\tversion = "{VERSION}",`,
		`\thash = {string.format("0x%08X", hash)},`,
		`\tscope = "{options.scope}",`,
		`\tside = "{self._side}",`,
		`\tidBytes = {Sizes.idBytes(server and self._toServer or self._toClient)},`,
	}

	if options.stamp then
		table.insert(lines, "\tstamp = true,")
	end

	if #labels > 0 then
		table.insert(lines, `\tstreams = \{ {table.concat(labels, ", ")} },`)
	end

	-- The dictionary message goes to the client, so it takes that direction's id width on both sides
	if self._dictionary then
		table.insert(lines, `\tdictionary = {Sizes.idBytes(self._toClient)},`)
	end

	if self._promise then
		table.insert(lines, "\tpromise = Promise,")
	end

	-- What the runtime labels each packet and each Heartbeat with, handed over only by a module whose readers label
	if self._label then
		table.insert(lines, "\tprofiler = debug,")
	end

	table.insert(lines, tables)
	table.insert(lines, "})")
	table.insert(lines, "")

	return table.concat(lines, "\n")
end

function Targets.method(self: Self, name: string): string
	return Types.cased(name, self._casing)
end

--[[
    The last id given in each direction, functions included, since a
    function's ids count towards the width; each channel's path by its
    number; whether any event is ordered; and whether any type is
    @dictionary
--]]

function Targets.count(self: Self, declarations: { Declaration })
	for _, declaration: Declaration in declarations do
		if declaration.kind == "namespace" then
			self:count(declaration.declarations)
		elseif declaration.kind == "channel" then
			self._streams[declaration.number :: number] = declaration.path :: string
		elseif declaration.kind == "type" then
			self._dictionary = self._dictionary or Sizes.dictionary(declaration)
		else
			self._toServer = math.max(self._toServer, declaration.toServer or 0)
			self._toClient = math.max(self._toClient, declaration.toClient or 0)
			self._ordered = self._ordered or (declaration.kind == "event" and declaration.type == "OrderedUnreliable")
		end
	end
end

--[[
    Marks every named type a function's return reaches, before any message
    is walked, so a return is checked whichever message walks the pair of
    a type it holds first, an event's included
--]]

function Targets.mark(self: Self, declarations: { Declaration })
	for _, declaration: Declaration in declarations do
		if declaration.kind == "namespace" then
			self:mark(declaration.declarations)
		elseif declaration.kind == "function" and declaration["return"] then
			-- Whiteoak TODO: unchecked, a marked pair checks its other uses too; a second, unchecked pair for them
			self._emitter:mark(declaration["return"] :: Type | Pack)
		end
	end
end

local _: TargetsTypes.Own, _: TargetsTypes.Api, _: TargetsTypes.Messages, _: TargetsTypes.Shards =
	Targets, Api, Messages, Shards

-- The API tables, the walk of an event and a side's shards are the methods of a sibling each; a name defined twice is a bug
local parts: { any } = { Api, Messages, Shards }

for _, part in parts do
	for name: string, method in part do
		assert(Targets[name] == nil, `Targets.{name} is defined twice`)
		Targets[name] = method
	end
end

return Targets
