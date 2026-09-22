--[[
    The API tables of a generated module: an entry per event, per function
    and per exported type, nested per namespace and frozen, then the
    members every module has, and the registry that lists every entry by
    its full name, which the wrapper binds by
--]]

--!strict
local Api = {} :: any

local Blocks = require("../Blocks")
local Messages = require("./Messages")
local Schema = require("../Config/Types/Schema")
local Types = require("./Types")

type Declaration = Schema.Declaration
type Event = Schema.Event
type Exchanged = Messages.Exchanged
type Function = Schema.Function
type TypeDeclaration = Schema.TypeDeclaration
type Walked = Messages.Walked

-- The fire variants a server event has beside fire, each one broadcast with the targets and the exception it names
local BROADCASTS: { { name: string, target: string, arguments: string } } = {
	{ name = "fireAll", target = "", arguments = "nil, nil" },
	{ name = "fireList", target = "players: { Player }", arguments = "players, nil" },
	{ name = "fireExcept", target = "player: Player", arguments = "nil, player" },
	{ name = "fireSet", target = "players: { [Player]: true }", arguments = "players, nil" },
}

local REGISTRIES: { string } = { "events", "functions", "exports" } -- The flat maps, in the order they are written

-- The parts of a list that are not empty, as one parameter or argument list
local function joined(...: string): string
	local parts: { string } = {}
	for _, part: string in { ... } do
		if part ~= "" then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, ", ")
end

-- An API member holding a function: its name, the signature and the body lines
local function member(name: string, signature: string, ...: string): string
	return `{name} = function {signature}\n\t{table.concat({ ... }, "\n\t")}\nend,`
end

-- The API table's entries: every message's and exported type's, nested per namespace, then the members every module has
function Api:api(): string
	local entries: { string } = self:declarations(self._file.declarations)
	local hooks: { string } = {
		`{self:method("hooks")} = table.freeze(\{`,
		`\t{self:method("beforeSend")} = runtime.beforeSend,`,
		`\t{self:method("afterReceive")} = runtime.afterReceive,`,
		"}),",
	}

	table.insert(entries, table.concat(hooks, "\n"))
	table.insert(entries, `{self:method("rate")} = runtime.rate,`)
	table.insert(entries, member(self:method("flush"), "()", "runtime:flush()"))
	table.insert(entries, member(self:method("onFailure"), "(handler: Volt.Failure)", "runtime:onFailure(handler)"))
	table.insert(entries, member(self:method("stats"), "(player: Player?): Volt.Stats", "return runtime:stats(player)"))

	return Blocks.paragraphs(entries)
end

--[[
    The API entries of a declaration list: an event's entry, a function's,
    an exported type's, and a namespace's frozen table of its own entries
--]]

function Api:declarations(declarations: { Declaration }): { string }
	local entries: { string } = {}

	for _, declaration: Declaration in declarations do
		if declaration.kind == "event" then
			table.insert(entries, self:event(declaration))
		elseif declaration.kind == "function" then
			table.insert(entries, self:call(declaration))
		elseif declaration.kind == "type" and declaration.export then
			table.insert(entries, self:export(declaration))
		elseif declaration.kind == "namespace" then
			local inner: string = Blocks.paragraphs(self:declarations(declaration.declarations))
			table.insert(entries, `{declaration.name} = table.freeze(\{\n{Blocks.indent(1, inner)}\n}),`)
		end
	end

	return entries
end

--[[
    The API entry of one event on this side: fire, asking the hook before
    its send first, with the broadcast variants on the server, when the
    side fires it; on, unless the event is polled, and iter when it hears
    it
--]]

function Api:event(event: Event): string
	local server: boolean = self._server
	local fires: boolean = event.from == "Both" or (event.from == "Server") == server
	local hears: boolean = event.from == "Both" or (event.from == "Server") ~= server
	local walked: Walked = self:walk(event, fires, hears)
	local members: { string } = {}

	if fires then
		local id: number = walked.out :: number
		local call: string = `write{walked.label}({walked.arguments})`
		local target: string = server and "player" or "nil"
		local allowed: string = `before[{id}] == nil or before[{id}]({joined(target, walked.arguments)})`

		if server then
			local guarded: string = `({joined("player: Player", walked.typed)})`
			local condition: string = `if ({allowed}) and runtime:target(player) then`

			table.insert(members, member(self:method("fire"), guarded, condition, `\t{call}`, "end"))

			for _, variant in BROADCASTS do
				local signature: string = `({joined(variant.target, walked.typed)})`
				local given: string = joined(tostring(id), variant.arguments, `write{walked.label}`, walked.arguments)

				table.insert(members, member(self:method(variant.name), signature, `runtime:broadcast({given})`))
			end
		else
			table.insert(
				members,
				member(self:method("fire"), `({walked.typed})`, `if {allowed} then`, `\t{call}`, "end")
			)
		end
	end

	if hears and event.call ~= "Polling" then
		local signature: string = `(listener: {walked.listener}): () -> ()`
		table.insert(members, member(self:method("on"), signature, `return runtime:on({walked.id}, listener)`))
	end

	if hears then
		local signature: string = `(): {walked.iterator}`
		table.insert(members, member(self:method("iter"), signature, `return runtime:iter({walked.id})`))
	end

	table.insert(self._registry.events, event.path :: string)

	return `{event.name} = table.freeze(\{\n{Blocks.indent(1, Blocks.paragraphs(members))}\n}),`
end

--[[
    The API entry of one function on this side: invoke on the client,
    which the runtime carries through the call's writer and answers with
    the reply; on for the one handler on the server
--]]

function Api:call(declaration: Function): string
	local exchanged: Exchanged = self:exchange(declaration)
	local entry: string

	if self._server then
		local signature: string = `(handler: {exchanged.handler}): () -> ()`
		entry = member(self:method("on"), signature, `return runtime:handle({exchanged.id}, handler)`)
	else
		local signature: string = `({exchanged.typed}){exchanged.result}`
		local passed: string = joined(`write{exchanged.label}`, exchanged.arguments)

		entry = member(self:method("invoke"), signature, `return runtime:invoke({exchanged.id}, {passed})`)
	end

	table.insert(self._registry.functions, declaration.path :: string)

	return `{declaration.name} = table.freeze(\{\n{Blocks.indent(1, entry)}\n}),`
end

--[[
    The API entry of an exported type: write, which serialises a value on
    its own into a buffer and its side array, and read, which takes one
    back, both through the type's shared pair
--]]

function Api:export(declaration: TypeDeclaration): string
	local pair: string = self._emitter:shared(declaration)
	local annotation: string = Types.label(declaration)
	local write: string = member(
		self:method("write"),
		`(value: {annotation}): (buffer, \{ any }?)`,
		`return runtime:encode(write{pair}, value)`
	)

	local read: string = member(
		self:method("read"),
		`(packet: buffer, side: \{ any }?): {annotation}`,
		`return runtime:decode(read{pair}, packet, side)`
	)

	table.insert(self._registry.exports, declaration.path :: string)
	return `{declaration.name} = table.freeze(\{\n{Blocks.indent(1, Blocks.paragraphs({ write, read }))}\n}),`
end

-- The registry: every event, function and exported type by its full name, each the same handle as its entry
function Api:registry(): string
	local maps: { string } = {}

	for _, kind: string in REGISTRIES do
		local entries: { string } = {}
		for _, path: string in self._registry[kind] do
			table.insert(entries, `\t["{path}"] = net.{path},`)
		end

		local inside: string = #entries == 0 and "{}" or `\{\n{table.concat(entries, "\n")}\n}`
		table.insert(maps, `net.{self:method(kind)} = table.freeze({inside})`)
	end

	return Blocks.paragraphs(maps)
end

return Api
