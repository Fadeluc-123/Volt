--[[
    The API tables of a generated module: an entry per event with fire
    and, on the server, the broadcast variants when the side fires it and
    on and iter when it hears it; an entry per function with invoke on
    the client and on for its handler on the server; nested per namespace
    and frozen, then the members every module has
--]]

--!strict
local Api = {} :: any

local Blocks = require("../Blocks")
local Messages = require("./Messages")
local Schema = require("../Config/Types/Schema")

type Declaration = Schema.Declaration
type Event = Schema.Event
type Exchanged = Messages.Exchanged
type Function = Schema.Function
type Walked = Messages.Walked

-- The fire variants a server event has beside fire, each writing to the scratch state and broadcasting from it
local BROADCASTS: { { name: string, target: string, arguments: string } } = {
	{ name = "fireAll", target = "", arguments = "" },
	{ name = "fireList", target = "players: { Player }", arguments = "players" },
	{ name = "fireExcept", target = "player: Player", arguments = "nil, player" },
	{ name = "fireSet", target = "players: { [Player]: true }", arguments = "players" },
}

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

-- The API table's entries: every message's, nested per namespace, then the members every module has
function Api:api(): string
	local entries: { string } = self:declarations(self._file.declarations)

	table.insert(entries, member(self:method("flush"), "()", "runtime:flush()"))
	table.insert(entries, member(self:method("onFailure"), "(handler: Volt.Failure)", "runtime:onFailure(handler)"))

	return Blocks.paragraphs(entries)
end

--[[
    The API entries of a declaration list: an event's entry, a function's,
    and a namespace's frozen table of its own entries
--]]

function Api:declarations(declarations: { Declaration }): { string }
	local entries: { string } = {}

	for _, declaration: Declaration in declarations do
		if declaration.kind == "event" then
			table.insert(entries, self:event(declaration))
		elseif declaration.kind == "function" then
			table.insert(entries, self:call(declaration))
		elseif declaration.kind == "namespace" then
			local inner: string = Blocks.paragraphs(self:declarations(declaration.declarations))
			table.insert(entries, `{declaration.name} = table.freeze(\{\n{Blocks.indent(1, inner)}\n}),`)
		end
	end

	return entries
end

--[[
    The API entry of one event on this side: fire, with the broadcast
    variants on the server, when the side fires it; on, unless the event
    is polled, and iter when it hears it
--]]

function Api:event(event: Event): string
	local server: boolean = self._server
	local fires: boolean = event.from == "Both" or (event.from == "Server") == server
	local hears: boolean = event.from == "Both" or (event.from == "Server") ~= server
	local walked: Walked = self:walk(event, fires, hears)
	local members: { string } = {}

	if fires and not server then
		table.insert(members, `{self:method("fire")} = write{walked.label},`)
	elseif fires then
		local send: string = event.type == "Reliable" and "reliable" or "unreliable"
		local call: string = `write{walked.label}({walked.arguments})`
		local guarded: string = `({joined("player: Player", walked.typed)})`
		local fire: string = member(self:method("fire"), guarded, "if runtime:target(player) then", `\t{call}`, "end")

		table.insert(members, fire)

		for _, variant in BROADCASTS do
			local signature: string = `({joined(variant.target, walked.typed)})`
			local broadcast: string = `runtime.{send}:broadcast({variant.arguments})`

			table.insert(members, member(self:method(variant.name), signature, "runtime:target(nil)", call, broadcast))
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
		local passed: string = joined(`write{exchanged.label}`, exchanged.arguments)
		entry = member(self:method("invoke"), `({exchanged.typed})`, `return runtime:invoke({exchanged.id}, {passed})`)
	end

	return `{declaration.name} = table.freeze(\{\n{Blocks.indent(1, entry)}\n}),`
end

return Api
