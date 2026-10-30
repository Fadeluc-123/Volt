--[[
    The API tables of a generated module: an entry per event, per function
    and per exported type, nested per namespace, frozen and cast to its
    handle type, then the members every module has, and the registry that
    lists every entry by its full name, which the wrapper binds by
--]]

--!strict
local Api = {}

local Blocks = require("../Blocks")
local Contract = require("../Config/Contract")
local Labels = require("./Labels")
local Schema = require("../Config/Types/Schema")
local TargetsTypes = require("../Config/Types/Targets")
local Types = require("./Types")

type Declaration = Schema.Declaration
type Entry = TargetsTypes.Entry
type Event = Schema.Event
type Exchanged = TargetsTypes.Exchanged
type Function = Schema.Function
type Targets = TargetsTypes.Targets
type TypeDeclaration = Schema.TypeDeclaration
type Walked = TargetsTypes.Walked

local VERSION: string = Contract.version

-- The fire variants a server event has beside fire, each one broadcast with the targets and the exception it names
local BROADCASTS: { { name: string, target: string, arguments: string } } = {
	{ name = "fireAll", target = "", arguments = "nil, nil" },
	{ name = "fireList", target = "players: { Player | Bot }", arguments = "players, nil" },
	{ name = "fireExcept", target = "player: Player | Bot", arguments = "nil, player" },
	{ name = "fireSet", target = "players: { [Player | Bot]: true }", arguments = "players, nil" },
}

-- The player callbacks a server module has, each handed to the runtime's method of the same name
local CALLBACKS: { string } = { "onJoin", "onLeave", "onHandshake" }

-- What a @delta fire with no player raises, as the runtime's target does for any other fire
local NONE: string = "Volt: a message for one player was sent to none"

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

-- An entry's members as a frozen table, cast to the handle type it fits so a checker holds every call to it
local function entry(members: { string }, handle: string): string
	return `table.freeze(\{\n{Blocks.indent(1, Blocks.paragraphs(members))}\n}) :: {handle}`
end

--[[
    The API table's entries: every message's and exported type's, nested
    per namespace, then the members every module has, flush labelled in a
    labelled module, and on the server the player callbacks, the byte
    count, the budget and the bot test after them. With values, each entry
    is its value by full name rather than its walk
--]]

function Api.api(self: Targets, values: { [string]: string }?): string
	local entries: { string } = self:declarations(self._file.declarations, values)
	local hooks: { string } = {
		`{self:method("hooks")} = table.freeze(\{`,
		`\t{self:method("beforeSend")} = runtime.beforeSend,`,
		`\t{self:method("afterReceive")} = runtime.afterReceive,`,
		"}),",
	}

	table.insert(entries, `{self:method("version")} = "{VERSION}",`)
	table.insert(entries, table.concat(hooks, "\n"))
	table.insert(entries, `{self:method("rate")} = runtime.rate,`)
	table.insert(entries, member(self:method("flush"), "()", Labels.flush(self._label)))

	local failure: string = "(handler: Volt.Failure): Volt.Failure"
	table.insert(entries, member(self:method("onFailure"), failure, "return runtime:onFailure(handler)"))

	local stats: string = "(player: (Player | Bot)?): Volt.Stats"
	table.insert(entries, member(self:method("stats"), stats, "return runtime:stats(player)"))

	-- A stamped client reads the server's clock through an accessor, never as an argument a listener takes
	if not self._server and self._file.options.stamp then
		table.insert(entries, member(self:method("serverTime"), "(): number", "return runtime:serverTime()"))
	end

	if not self._server then
		return Blocks.paragraphs(entries)
	end

	for _, callback: string in CALLBACKS do
		local signature: string = "(callback: (player: Player | Bot) -> ()): () -> ()"
		table.insert(entries, member(self:method(callback), signature, `return runtime:{callback}(callback)`))
	end

	local traffic: string = "(player: Player | Bot): (number, number)"
	table.insert(entries, member(self:method("traffic"), traffic, "return runtime:traffic(player)"))
	table.insert(entries, member(self:method("budget"), "(bytesPerSecond: number?)", "runtime:budget(bytesPerSecond)"))
	table.insert(entries, `{self:method("isBot")} = runtime.isBot,`)

	return Blocks.paragraphs(entries)
end

--[[
    The API entries of a declaration list: an event's entry, a function's,
    an exported type's, and a namespace's frozen table of its own entries.
    Each walked entry is recorded with the functions its walk added, so a
    side that shards can move it whole; with values, nothing is walked
--]]

function Api.declarations(self: Targets, declarations: { Declaration }, values: { [string]: string }?): { string }
	local entries: { string } = {}

	for _, declaration: Declaration in declarations do
		local first: number = #self._functions + 1
		local value: string? = nil

		if declaration.kind == "namespace" then
			local inner: string = Blocks.paragraphs(self:declarations(declaration.declarations, values))
			table.insert(entries, `{declaration.name} = table.freeze(\{\n{Blocks.indent(1, inner)}\n}),`)
		elseif values then
			value = values[declaration.path :: string]
		elseif declaration.kind == "event" then
			value = self:event(declaration)
		elseif declaration.kind == "function" then
			value = self:call(declaration)
		elseif declaration.kind == "type" and declaration.export then
			value = self:export(declaration)
		end

		if value then
			table.insert(entries, `{declaration.name} = {value},`)
		end

		if value and not values then
			local path: string = declaration.path :: string
			local walked: Entry =
				{ path = path, declaration = declaration, value = value, first = first, last = #self._functions }

			table.insert(self._entries, walked)
		end
	end

	return entries
end

--[[
    The API entry of one event on this side: fire, asking the hook before
    its send first, with the broadcast variants on the server, when the
    side fires it; on, unless the event is polled, and iter when it hears
    it. A two-way entry is cast to both handles it fits. Every fire of a
    @delta event hands its targets to the runtime's delta, which asks the
    hook and points the send itself, so fire refuses only a missing player
--]]

function Api.event(self: Targets, event: Event): string
	local server: boolean = self._server
	local fires: boolean = event.from == "Both" or (event.from == "Server") == server
	local hears: boolean = event.from == "Both" or (event.from == "Server") ~= server
	local walked: Walked = self:walk(event, fires, hears)
	local realm: string = server and "Server" or "Client"
	local members: { string } = {}
	local handles: { string } = {}

	if fires then
		local id: number = walked.out :: number
		local call: string = `write{walked.label}({walked.arguments})`

		-- An unchecked writer fires through the runtime, so a value that raises part way leaves nothing behind
		if self._file.options.writeValidation == false then
			call = `runtime:write({joined(tostring(id), `write{walked.label}`, walked.arguments)})`
		end
		local target: string = server and "player" or "nil"
		local allowed: string = `before[{id}] == nil or before[{id}]({joined(target, walked.arguments)})`

		if server then
			-- An event on a channel points that channel's send at the player, by its number
			local guarded: string = `({joined("player: Player | Bot", walked.typed)})`
			local targeted: string =
				`runtime:target({joined("player", walked.stream and tostring(walked.stream) or "")})`
			local condition: string = `if ({allowed}) and {targeted} then`
			local through: string = walked.delta and "delta" or "broadcast"

			if walked.delta then
				local given: string = joined(tostring(id), "player, nil, nil", `write{walked.label}`, walked.arguments)
				local present: string = `assert(player ~= nil, "{NONE}")`

				table.insert(members, member(self:method("fire"), guarded, present, `runtime:delta({given})`))
			else
				table.insert(members, member(self:method("fire"), guarded, condition, `\t{call}`, "end"))
			end

			for _, variant in BROADCASTS do
				local signature: string = `({joined(variant.target, walked.typed)})`
				local targets: string = walked.delta and `nil, {variant.arguments}` or variant.arguments
				local given: string = joined(tostring(id), targets, `write{walked.label}`, walked.arguments)

				table.insert(members, member(self:method(variant.name), signature, `runtime:{through}({given})`))
			end
		else
			table.insert(
				members,
				member(self:method("fire"), `({walked.typed})`, `if {allowed} then`, `\t{call}`, "end")
			)
		end

		table.insert(handles, `{realm}Event<{walked.pack}>`)
	end

	if hears and event.call ~= "Polling" then
		local signature: string = `(listener: {walked.listener}): () -> ()`
		table.insert(members, member(self:method("on"), signature, `return runtime:on({walked.id}, listener)`))
	end

	if hears then
		local signature: string = `(): {walked.iterator}`
		local polled: boolean = event.call == "Polling"

		table.insert(members, member(self:method("iter"), signature, `return runtime:iter({walked.id})`))
		table.insert(handles, `{realm}{polled and "Polling" or "Listener"}<{walked.pack}>`)
	end

	table.insert(self._registry.events, event.path :: string)

	return entry(members, table.concat(handles, " & "))
end

--[[
    The API entry of one function on this side: invoke on the side its
    from names, which the runtime carries through the call's writer and
    answers with the reply, the server's taking the player first; on for
    the one handler on the other, and on the client connected beside it
--]]

function Api.call(self: Targets, declaration: Function): string
	local server: boolean = self._server
	local exchanged: Exchanged = self:exchange(declaration)
	local packs: string = `<{exchanged.pack}, {exchanged.returns}>`
	local members: { string } = {}
	local handle: string

	if (declaration.from == "Server") ~= server then
		local signature: string = `(handler: {exchanged.handler}): () -> ()`

		handle = server and `ServerFunction{packs}` or `ClientHandler{packs}`
		table.insert(members, member(self:method("on"), signature, `return runtime:handle({exchanged.id}, handler)`))

		if not server then
			local connected: string = `return runtime:handled({exchanged.id})`
			table.insert(members, member(self:method("connected"), "(): boolean", connected))
		end
	else
		local player: string = server and "player: Player | Bot" or ""
		local signature: string = `({joined(player, exchanged.typed)}){exchanged.result}`
		local passed: string = joined(`write{exchanged.label}`, server and "player" or "", exchanged.arguments)
		local invoke: string = `return runtime:invoke({exchanged.id}, {passed})`
		local realm: string = server and "Server" or "Client"

		handle = declaration.yield == "Promise" and `{realm}Promise<{exchanged.pack}>`
			or `{realm}{server and "Invoke" or "Function"}{packs}`
		table.insert(members, member(self:method("invoke"), signature, invoke))
	end

	table.insert(self._registry.functions, declaration.path :: string)

	return entry(members, handle)
end

--[[
    The API entry of an exported type: write, which serialises a value on
    its own into a buffer and its side array, and read, which takes one
    back, both through the type's shared pair
--]]

function Api.export(self: Targets, declaration: TypeDeclaration): string
	local pair: string = self._emitter:shared(declaration)
	local annotation: string = Types.label(declaration)
	local write: string = member(
		self:method("write"),
		`(value: {annotation}): (buffer, \{ any }?)`,
		`return runtime:encode("{declaration.path}", write{pair}, value)`
	)

	local read: string = member(
		self:method("read"),
		`(packet: buffer, side: \{ any }?): {annotation}`,
		`return runtime:decode(read{pair}, packet, side)`
	)

	table.insert(self._registry.exports, declaration.path :: string)
	return entry({ write, read }, `Exported<{annotation}>`)
end

--[[
    The registry: every event, function and exported type by its full
    name, each the same handle as its entry, cast to a map a binder can
    index with a name it holds and walk
--]]

function Api.registry(self: Targets): string
	local maps: { string } = {}

	for _, kind: string in REGISTRIES do
		local entries: { string } = {}
		for _, path: string in self._registry[kind] do
			table.insert(entries, `\t["{path}"] = Network.{path},`)
		end

		local inside: string = #entries == 0 and "{}" or `\{\n{table.concat(entries, "\n")}\n}`
		table.insert(maps, `Network.{self:method(kind)} = table.freeze({inside}) :: \{ [string]: any }`)
	end

	return Blocks.paragraphs(maps)
end

return Api
