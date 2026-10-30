--[[
    The pieces a module's assembly chooses from and how it chooses: the
    send functions its writers may name, every piece a side's walk made,
    the names a text reaches for, the pieces and send locals a text keeps,
    a schema table's rows and where a shard is written
--]]

--!strict
local Pieces = {}

local Contract = require("../Config/Contract")
local EmitTypes = require("../Config/Types/Emit")
local Helpers = require("../Emit/Helpers")
local Output = require("../Config/Output")

type Emit = EmitTypes.Emit
type Parameter = Contract.Parameter

-- A send function of the runtime as a writer names it, and where it is taken from once the runtime exists
export type Send = { name: string, type: string, from: string }

local SHARD: string = Output.shard

-- What a reliable or an unreliable send hands a writer, a channel's among them
local SEND: { Parameter } = { Contract.begin, Contract.trim, table.unpack(Contract.write) }

-- An ordered event's sequence, which only a module of a schema with an ordered event may name
local ORDER: Send = { name = "orderUnreliable", type = "(number) -> number", from = "runtime.unreliable.order" }

-- The send functions every module's writers may name, in the order they are declared; filled from the contract below
local SENDS: { Send } = {}

for _, reliability: string in { "Reliable", "Unreliable" } do
	for _, parameter: Parameter in SEND do
		table.insert(SENDS, {
			name = `{parameter.name}{reliability}`,
			type = parameter.type,
			from = `runtime.{reliability:lower()}.{parameter.name}`,
		})
	end
end

table.insert(SENDS, { name = "markUnreliable", type = "() -> ()", from = "runtime.unreliable.mark" })

-- An AwaitedInstance's id, which a server writer takes and a client reader looks up, a shared pair's included
table.insert(SENDS, { name = "instanceId", type = "(Instance) -> number", from = "runtime.instanceId" })
table.insert(SENDS, { name = "instanceById", type = "(number) -> Instance?", from = "runtime.instanceById" })

-- A @dictionary string's id, which a server writer takes, and the entries a client reader looks one up in
table.insert(SENDS, { name = "internDictionary", type = "(string) -> number", from = "runtime.intern" })
table.insert(SENDS, { name = "dictionaryEntries", type = "{ string }", from = "runtime.dictionary" })

--[[
    The send functions a schema's writers may name, in the order a module
    declares them: every module's, then an ordered event's sequence, then
    each channel's reliable send by its number, suffixed with its label.
    Returns them and the names that are the schema's own, which no
    writer's field or parameter may shadow
--]]

function Pieces.sends(streams: { string }, ordered: boolean): ({ Send }, { string })
	local sends: { Send } = table.clone(SENDS)
	local own: { string } = {}

	if ordered then
		table.insert(sends, ORDER)
	end

	for index: number, path: string in streams do
		local label: string = path:gsub("%.", "_")

		for _, parameter: Parameter in SEND do
			local from: string = `runtime.streams[{index}].{parameter.name}`
			table.insert(sends, { name = `{parameter.name}Reliable_{label}`, type = parameter.type, from = from })
		end
	end

	for index: number = #SENDS + 1, #sends do
		table.insert(own, sends[index].name)
	end

	return sends, own
end

--[[
    The module-level names a text reaches for, each one it calls, indexes
    or hands on, never a field so named nor one it only assigns to. The
    text is read once, so a module's assembly reads each piece once
--]]

function Pieces.reached(text: string): { [string]: boolean }
	-- A refusal's message opens with the message's name, so a string's text is blanked first, escapes before quotes
	local code: string = text:gsub("\\.", ""):gsub('"[^"]*"', '""')
	local names: { [string]: boolean } = {}

	for start: number in code:gmatch("()[%w_]+") do
		local name: string = code:match("^[%w_]+", start) :: string
		local before: string = code:sub(start - 1, start - 1)

		if before ~= "." and before ~= ":" and code:match("^%s*(=?=?)", start + #name) ~= "=" then
			names[name] = true
		end
	end

	return names
end

-- The one module-level local a piece or a generated function declares
function Pieces.name(piece: string): string
	return piece:match("local function ([%w_]+)") or piece:match("local ([%w_]+)") :: string
end

--[[
    Every piece a side's walk made, in the order a module declares them:
    the helpers by name, then the constants, then the shared halves, each
    after the halves it calls
--]]

function Pieces.list(emitter: Emit): { string }
	local helpers: { string } = {}
	local pieces: { string } = {}

	for helper: string in emitter.helpers do
		table.insert(helpers, helper)
	end

	table.sort(helpers)

	for _, helper: string in helpers do
		table.move(Helpers[helper], 1, #Helpers[helper], #pieces + 1, pieces)
	end
	for _, constant: string in emitter.constants do
		table.insert(pieces, `{constant}\n`)
	end

	table.move(emitter.functions, 1, #emitter.functions, #pieces + 1, pieces)

	return pieces
end

--[[
    The module-level pieces a module keeps, each a helper, a constant or
    one half of a shared pair: walked from the last, since a piece names
    only those above it, and kept when the text below that is kept names
    the one local it declares
--]]

function Pieces.kept(pieces: { string }, below: string): { string }
	local list: { string } = {}
	local reached: { [string]: boolean } = Pieces.reached(below)

	for index: number = #pieces, 1, -1 do
		local piece: string = pieces[index]

		if reached[Pieces.name(piece)] then
			table.insert(list, 1, piece)

			for name: string in Pieces.reached(piece) do
				reached[name] = true
			end
		end
	end

	return list
end

--[[
    What a module's text needs above it: the pieces it keeps, then the
    send locals those and the text name, each in the order a module
    declares them
--]]

function Pieces.needed(pieces: { string }, sends: { Send }, text: string): ({ string }, { Send })
	local kept: { string } = Pieces.kept(pieces, text)
	local reached: { [string]: boolean } = Pieces.reached(`{text}\n{table.concat(kept, "\n")}`) -- A kept pair's too
	local named: { Send } = {}

	for _, send: Send in sends do
		if reached[send.name] then
			table.insert(named, send)
		end
	end

	return kept, named
end

-- How many module-level locals a module's text declares, one to a line and none indented
function Pieces.declared(text: string): number
	local _, count: number = text:gsub("\nlocal ", "")
	return count
end

-- Where a side's shard is written: beside its entry, named for it with the shard's number before the extension
function Pieces.shardPath(output: string, index: number): string
	local stem: string?, extension: string? = output:match("^(.-)(%.[^./\\]*)$")
	return `{stem or output}{SHARD}{index}{extension or ""}`
end

-- The rows of a schema table by id, or an empty table when the side has none
function Pieces.rows(list: { [number]: string }, count: number): string
	local lines: { string } = {}
	for id: number = 1, count do
		if list[id] then
			table.insert(lines, `\t\t[{id}] = {list[id]},`)
		end
	end
	return #lines == 0 and "{}" or `\{\n{table.concat(lines, "\n")}\n\t}`
end

return Pieces
