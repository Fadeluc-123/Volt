--[[
    A side too big for one file, written as an entry and its shards: the
    entries packed into shards in declaration order, each shard's text, and
    the entry's, which requires them, starts the runtime with their readers
    and builds the API a one-file module has from the handles they hold
--]]

--!strict
local Shards = {}

local Blocks = require("../Blocks")
local Contract = require("../Config/Contract")
local Diagnostics = require("../Diagnostics")
local Output = require("../Config/Output")
local Pieces = require("./Pieces")
local TargetsTypes = require("../Config/Types/Targets")

type Diagnostics = Diagnostics.Diagnostics
type Entry = TargetsTypes.Entry
type Extra = TargetsTypes.Extra
type Send = Pieces.Send
type Targets = TargetsTypes.Targets

local VERSION: string = Contract.version
local FILE_LOCALS: number = Output.fileLocals

-- What a shard's header says it is: which of its side's shards, and of which module
local function about(self: Targets, name: string, index: number, count: number): string
	return table.concat({
		`    Shard {index} of {count} of the {self._side} module Volt {VERSION} generated from {name}:`,
		"    the writers and readers of some of its messages, with the handles its",
		"    entry module builds the API from. Generated code: change the schema and",
		"    run volt again rather than editing this file",
	}, "\n")
end

--[[
    The module-level names a shard declares for one entry: its functions,
    the pieces they and its handle reach, the send locals those name, and
    before when a fire asks its hook first
--]]

local function names(self: Targets, entry: Entry, pieces: { string }): { [string]: boolean }
	local functions: string = table.concat(self._functions, "\n", entry.first, entry.last)
	local kept: { string }, sends: { Send } = Pieces.needed(pieces, self._sends, `{functions}\n{entry.value}`)
	local set: { [string]: boolean } = {}

	for index: number = entry.first, entry.last do
		set[Pieces.name(self._functions[index])] = true
	end
	for _, piece: string in kept do
		set[Pieces.name(piece)] = true
	end
	for _, send: Send in sends do
		set[send.name] = true
	end

	if entry.value:find("before[", 1, true) then
		set.before = true
	end

	return set
end

--[[
    Packs the entries into shards in declaration order: a shard takes the
    next entry while it holds fewer than shardSize and the locals it would
    declare, fixed for its header and runtime and one per name its entries
    need, stay within FILE_LOCALS; otherwise the next shard begins. An
    entry that passes FILE_LOCALS alone is refused, since no split fits it
--]]

function Shards.pack(self: Targets, pieces: { string }, fixed: number, diagnostics: Diagnostics): { { Entry } }
	local size: number = self._file.options.shardSize or math.huge
	local shards: { { Entry } } = { {} }
	local held: { [string]: boolean } = {}
	local count: number = fixed

	for _, entry: Entry in self._entries do
		local own: { [string]: boolean } = names(self, entry, pieces)
		local alone: number, added: number = fixed, 0

		for name: string in own do
			alone += 1
			added += held[name] and 0 or 1
		end

		if alone > FILE_LOCALS then
			local needs: string = `{entry.path} needs {alone} module-level locals on the {self._side}`
			diagnostics:error("V4003", `{needs}, more than one generated file holds ({FILE_LOCALS})`, entry.declaration)
		end

		local shard: { Entry } = shards[#shards]

		if #shard > 0 and (#shard >= size or count + added > FILE_LOCALS) then
			shard, held, count, added = {}, {}, fixed, alone - fixed
			table.insert(shards, shard)
		end

		table.insert(shard, entry)
		count += added

		for name: string in own do
			held[name] = true
		end
	end

	return shards
end

--[[
    One shard's text: its header, every type as a local line, the locals
    its functions name, declared here and assigned when the entry binds
    it, the pieces they reach and its entries' functions, then the table
    the entry takes them from: bind, each reader and reply writer the
    schema table names, and each entry's handle by its full name
--]]

function Shards.shard(self: Targets, entries: { Entry }, pieces: { string }, head: string, schema: string): string
	local functions: { string } = {}
	local handles: { string } = {}

	for _, entry: Entry in entries do
		table.move(self._functions, entry.first, entry.last, #functions + 1, functions)
		table.insert(handles, `["{entry.path}"] = {entry.value},`)
	end

	local held: string = Blocks.paragraphs(handles)
	local kept: { string }, sends: { Send } =
		Pieces.needed(pieces, self._sends, `{table.concat(functions, "\n")}\n{held}`)
	local declared: { string } = { "local runtime: Volt.Runtime" }
	local bound: { string } = { "runtime = started" }
	local returned: { string } = {}

	for _, send: Send in sends do
		table.insert(declared, `local {send.name}: {send.type}`)
		table.insert(bound, `{send.name} = {send.from}`)
	end

	-- A fire asks the hook before its send, whose table the runtime holds once it is started
	if held:find("before[", 1, true) then
		table.insert(declared, "local before: { [number]: Volt.Hook }")
		table.insert(bound, "before = runtime.before")
	end

	table.insert(returned, `bind = function (started: Volt.Runtime)\n\t{table.concat(bound, "\n\t")}\nend,`)

	-- The entry's schema table reads each message heard, and each reply writer, out of the shard that holds it
	local rows: { [string]: boolean } = Pieces.reached(schema)

	for _, text: string in functions do
		local name: string = Pieces.name(text)

		if rows[name] then
			table.insert(returned, `{name} = {name},`)
		end
	end

	table.insert(returned, `handles = \{\n{Blocks.indent(1, held)}\n},`)

	local parts: { string } = { head }
	local aliases: { string } = self:aliases(true)

	table.move(aliases, 1, #aliases, #parts + 1, parts)
	table.insert(parts, `{table.concat(declared, "\n")}\n`)
	table.move(kept, 1, #kept, #parts + 1, parts)
	table.move(functions, 1, #functions, #parts + 1, parts)
	table.insert(parts, `return \{\n{Blocks.indent(1, Blocks.paragraphs(returned))}\n}\n`)

	return table.concat(parts, "\n")
end

--[[
    The entry and its shards for a side that shards. Each shard is written
    beside the entry's output and required by its name; the entry starts
    the runtime with each row's reader and reply writer read out of its
    shard, binds the shards in order and builds the API table and the
    registry from their handles. More shards than the entry can declare
    locals for is refused at the top of the options file
--]]

function Shards.sharded(
	self: Targets,
	hash: number,
	name: string,
	pieces: { string },
	diagnostics: Diagnostics
): (string, { Extra })
	local output: string = (
		self._server and self._file.options.serverOutput or self._file.options.clientOutput
	) :: string
	local file: string = output:match("[^/\\]+$") or output
	local within: string = file:match("^init%.") and "@self/" or "./" -- An init file's ./ names its folder's parent
	local fixed: number = Pieces.declared(self:header(about(self, name, 1, 1), false)) + 1 -- With runtime
	local shards: { { Entry } } = self:pack(pieces, fixed, diagnostics)
	local schema: string = self:start(hash)
	local rows: { [string]: string } = {} -- Each function the schema table may name, as its row reads it
	local values: { [string]: string } = {}
	local requires: { string } = {}
	local binds: { string } = {}
	local extra: { Extra } = {}

	for index: number, entries: { Entry } in shards do
		local shard: string = `Shard{index}`
		local base: string = Pieces.shardPath(file, index):gsub("%.[^.]*$", "")
		local head: string = self:header(about(self, name, index, #shards), false)

		table.insert(requires, `local {shard} = require("{within}{base}")`)
		table.insert(binds, `{shard}.bind(runtime)`)
		table.insert(
			extra,
			{ output = Pieces.shardPath(output, index), text = self:shard(entries, pieces, head, schema) }
		)

		for _, entry: Entry in entries do
			values[entry.path] = `{shard}.handles["{entry.path}"]`

			for at: number = entry.first, entry.last do
				local named: string = Pieces.name(self._functions[at])
				rows[named] = `= {shard}.{named}`
			end
		end
	end

	local plural: string = #shards == 1 and "" or "s"
	local described: string = table.concat({
		`    The {self._side} module Volt {VERSION} generated from {name}, as an entry`,
		`    and {#shards} shard{plural} beside it: the schema table the runtime starts from and`,
		"    the API a game calls, built from the handles the shards hold beside",
		"    each message's writer and reader. Generated code: change the schema",
		"    and run volt again rather than editing these files",
	}, "\n")
	local parts: { string } = { `{self:header(described, self._promise)}{table.concat(requires, "\n")}\n` }
	local aliases: { string } = self:aliases(false)

	table.move(aliases, 1, #aliases, #parts + 1, parts)
	table.insert(parts, "local runtime: Volt.Runtime\n")
	table.insert(parts, (schema:gsub("= ([%a_][%w_]*)", rows)))
	table.insert(parts, `{table.concat(binds, "\n")}\n`)
	table.insert(parts, `local Network = \{\n{Blocks.indent(1, self:api(values))}\n}\n`)
	table.insert(parts, `{self:registry()}\n`)
	table.insert(parts, "return table.freeze(Network)\n")

	local text: string = table.concat(parts, "\n")
	local most: number = FILE_LOCALS - Pieces.declared(text) + #shards

	if #shards > most then
		local top: { start: number, finish: number } =
			{ start = diagnostics.source.start, finish = diagnostics.source.start }
		local needs: string = `the {self._side} module needs {#shards} shards`
		diagnostics:error("V4003", `{needs}, more than its entry can require ({most})`, top)
	end

	return text, extra
end

return Shards
