--[[
    Binds every name in a parsed schema to its declaration through the
    namespace rules, a generic's parameters first inside its body, fills
    the option and message defaults, and reports unknown and duplicate
    names, wrong argument counts, missing options and numbers that are not
    positive, then runs Expand, so later stages walk a tree in which every
    lookup succeeds
--]]

--!strict
local Resolve = {}
Resolve.__index = Resolve

local Attributes = require("./Config/Attributes")
local Diagnostics = require("./Diagnostics")
local Expand = require("./Expand")
local Options = require("./Config/Options")
local Parser = require("./Parser")
local Schema = require("./Config/Types/Schema")
local Source = require("./Source")

type Attribute = Attributes.Attribute
type Declaration = Schema.Declaration
type Diagnostics = Diagnostics.Diagnostics
type Event = Schema.Event
type File = Schema.File
type Options = Schema.Options
type Pack = Schema.Pack
type Parameter = Schema.Parameter
type Source = Source.Source
type Span = Diagnostics.Span
type Spec = Options.Spec
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration

local KINDS: { [string]: string } = {
	type = "a type",
	event = "an event",
	channel = "a channel",
	namespace = "a namespace",

	["function"] = "a function",
}

type Fields = {
	_diagnostics: Diagnostics,
	_names: { [string]: Declaration },
	_promise: Span?,
}

--[[
    Fills the keys of a message that default from a file option, as the
    shape names them
--]]

local function defaults(target: { [string]: any }, shape: { Spec }, options: Options)
	for _, spec: Spec in shape do
		if spec.option and target[spec.key] == nil then
			target[spec.key] = (options :: any)[spec.option]
		end
	end
end

--[[
    Resolves a parsed file in place: options and message keys take their
    defaults, every declaration gets its full path and every reference its
    target, then Expand turns spreads and generics into plain named types
--]]

function Resolve.file(file: File, diagnostics: Diagnostics)
	local self: Self = setmetatable({
		_diagnostics = diagnostics,
		_names = {} :: { [string]: Declaration },
		_promise = nil :: Span?, -- What first asked for a promise yield
	}, Resolve)

	self:options(file.options, diagnostics.source)
	self:declare(file.declarations, "")
	self:bind(file.declarations, "", file.options)

	if self._promise and file.options.promise == nil then
		self._diagnostics:error(
			"V3004",
			"missing option promise; a promise yield needs the library's path",
			self._promise
		)
	end

	Expand.file(file, diagnostics)
end

--[[
    Reports the options that must be present, fills in every default and
    checks the numbers; the scope defaults to the options file's own name,
    and a missing option is reported at the top of that file
--]]

function Resolve.options(self: Self, options: Options, source: Source)
	local top: Span = { start = source.start, finish = source.start }
	local path: string = source.path
	local keyed: { [string]: any } = options :: { [string]: any } -- Read and filled by key, as the shape lists them

	for _, spec: Spec in Options.file do
		if keyed[spec.key] ~= nil then
			continue
		elseif spec.required then
			self._diagnostics:error("V3004", `missing option {spec.key}`, top)
		end

		keyed[spec.key] = spec.default
	end

	self:positive(keyed, Options.file)

	-- A threshold has nothing to add to a cadence that sends every frame
	if options.flushBytes and options.flush == 1 and not options.manualReplication then
		self._diagnostics:warn("V3013", "flushBytes means nothing when every frame flushes", options.spans.flushBytes)
	end

	options.scope = options.scope or path:match("([^/\\]+)%.volt$") or path
	options.stamp = options.stamp or nil -- Off is the schema with no stamp, so it prints and hashes as one

	if options.yield == "promise" then
		self._promise = options.spans.yield
	end
end

--[[
    Reports a numeric key that is zero, negative or, where a whole number
    is needed, fractional. A key the target does not carry is skipped
--]]

function Resolve.positive(self: Self, target: { [string]: any }, shape: { Spec })
	for _, spec: Spec in shape do
		local value: any = target[spec.key]

		if spec.kind ~= "number" or typeof(value) ~= "number" then
			continue
		end

		if value <= 0 or (not spec.fractional and value % 1 ~= 0) then
			local wanted: string = spec.fractional and "number" or "integer"
			self._diagnostics:error(
				"V3005",
				`{spec.key} must be a positive {wanted}, got {value}`,
				target.spans[spec.key]
			)
		end
	end
end

--[[
    Reports an attribute's argument that is not a positive whole number or
    is past the most its row allows
--]]

function Resolve.attributes(self: Self, declaration: TypeDeclaration)
	for _, row: Attribute in Attributes do
		local value: any = declaration.attributes and declaration.attributes[row.name]

		if row.argument and value then
			local span: Span = (declaration.spans :: { [string]: Span })[row.name]

			if value <= 0 or value % 1 ~= 0 then
				self._diagnostics:error("V3005", `@{row.name} must be a positive integer, got {value}`, span)
			elseif row.most and value > row.most then
				self._diagnostics:error("V3005", `@{row.name} must be at most {row.most}, got {value}`, span)
			end
		end
	end
end

--[[
    Records every declaration under its full path, so a forward reference
    resolves, and keeps the first of two declarations with the same path
--]]

function Resolve.declare(self: Self, declarations: { Declaration }, prefix: string)
	for _, declaration: Declaration in declarations do
		local path: string = prefix == "" and declaration.name or `{prefix}.{declaration.name}`
		if self._names[path] then
			self._diagnostics:error("V3002", `"{path}" is declared twice`, declaration)
		else
			self._names[path] = declaration
		end

		(declaration :: any).path = path

		if declaration.kind == "type" then
			declaration.references = 0
		elseif declaration.kind == "namespace" then
			self:declare(declaration.declarations, path)
		end
	end
end

--[[
    Binds the references inside every declaration and an event's channel,
    and gives each message the defaults its keys did not set, after
    checking the keys it did. A channel has nothing to bind
--]]

function Resolve.bind(self: Self, declarations: { Declaration }, prefix: string, options: Options)
	for _, declaration: Declaration in declarations do
		if declaration.kind == "type" then
			self:attributes(declaration)
			self:type(declaration.type, prefix, declaration.parameters)
		elseif declaration.kind == "namespace" then
			self:bind(declaration.declarations, declaration.path :: string, options)
		elseif declaration.kind == "event" then
			local rate: Span? = declaration.spans.rate
			self:positive(declaration :: { [string]: any }, Options.event)

			if declaration.from == "Server" and rate then
				local message: string =
					"rate on a Server event has no effect; only client-to-server messages are limited"
				self._diagnostics:warn("V3006", message, rate)
			end

			defaults(declaration :: { [string]: any }, Options.event, options)

			if declaration.data then
				self:type(declaration.data, prefix)
			end

			if declaration.channel then
				self:channel(declaration, prefix)
			end
		elseif declaration.kind == "function" then
			local rate: Span? = declaration.spans.rate
			self:positive(declaration :: { [string]: any }, Options["function"])

			if declaration.from == "Server" and rate then
				local message: string =
					"rate on a from: Server function has no effect; the server limits no reply it reads"
				self._diagnostics:warn("V3006", message, rate)
			end

			-- from takes no default, so a function without it stays a client's call and prints as it always did
			defaults(declaration :: { [string]: any }, Options["function"], options)

			-- The file's yield is spelled in lower case and a function's in upper, so it is not a plain default
			declaration.yield = declaration.yield or (options.yield == "promise" and "Promise" or "Coroutine")

			if declaration.yield == "Promise" then
				self._promise = self._promise or declaration.spans.yield
			end

			if declaration.data then
				self:type(declaration.data, prefix)
			end

			if declaration["return"] then
				self:type(declaration["return"], prefix)
			end
		end
	end
end

--[[
    Binds an event's channel, a plain name found from the event's namespace
    outward as a type is, to the channel's full path. A channel carries
    Reliable events only, and each refusal is reported at the channel key
--]]

function Resolve.channel(self: Self, event: Event, prefix: string)
	local name: string = event.channel :: string
	local key: Span = event.spans.channel
	local found: Declaration? = self:lookup(prefix, name)

	if not found then
		self._diagnostics:error("V3001", `unknown channel "{name}"`, key)
	elseif found.kind ~= "channel" then
		self._diagnostics:error("V3001", `"{name}" is {KINDS[found.kind]}, not a channel`, key)
	elseif event.type ~= "Reliable" then
		local message: string = `event {event.path} is {event.type}; a channel carries Reliable events only`
		self._diagnostics:error("V3014", message, key)
	else
		event.channel = found.path
	end
end

--[[
    Binds every reference inside a type where it is written, its arguments
    included: to a parameter of the generic whose body it sits in, by that
    parameter's index, or to the named type it reaches from its namespace,
    when it passes as many arguments as that type takes parameters
--]]

function Resolve.type(self: Self, node: Type | Pack, prefix: string, parameters: { Parameter }?)
	for _, child: Type in Parser.children(node) do
		self:type(child, prefix, parameters)
	end

	if node.kind ~= "reference" then
		return
	end

	for index: number, parameter: Parameter in parameters or {} do
		if parameter.name == node.name then
			if node.arguments then
				self._diagnostics:error("V3007", `type parameter "{node.name}" takes no type arguments`, node)
			end

			node.parameter = index
			return
		end
	end

	local found: Declaration? = self:lookup(prefix, node.name)

	if not found then
		self._diagnostics:error("V3001", `unknown type "{node.name}"`, node)
	elseif found.kind ~= "type" then
		self._diagnostics:error("V3001", `"{node.name}" is {KINDS[found.kind]}, not a type`, node)
	else
		local takes: number = found.parameters and #found.parameters or 0
		local given: number = node.arguments and #node.arguments or 0

		if takes ~= given then
			local wanted: string = takes == 0 and "no type arguments"
				or `{takes} type argument{takes == 1 and "" or "s"}`
			self._diagnostics:error("V3007", `"{node.name}" takes {wanted}, got {given}`, node)
		else
			node.target = found
		end
	end
end

--[[
    Finds a name from inside a namespace: the namespace's own declarations
    first, then each enclosing namespace's, then the top level, so a name
    written with a namespace prefix reaches into any namespace from anywhere
--]]

function Resolve.lookup(self: Self, prefix: string, name: string): Declaration?
	local scope: string = prefix

	while true do
		local found: Declaration? = self._names[scope == "" and name or `{scope}.{name}`]

		if found or scope == "" then
			return found
		end

		scope = scope:match("^(.*)%.[^.]*$") or ""
	end
end

type Self = typeof(setmetatable({} :: Fields, Resolve))

return Resolve
