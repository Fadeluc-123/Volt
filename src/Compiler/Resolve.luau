--[[
    Binds every name in a parsed schema to its declaration through the
    namespace rules, fills the option and message defaults, and reports
    unknown and duplicate names, recursive types, missing options and
    numbers that are not positive, so later stages walk a tree in which
    every lookup succeeds
--]]

--!strict
local Resolve = {} :: any
Resolve.__index = Resolve

local Diagnostics = require("./Diagnostics")
local Parser = require("./Parser")

type Declaration = Parser.Declaration
type Diagnostics = Diagnostics.Diagnostics
type File = Parser.File
type Options = Parser.Options
type Pack = Parser.Pack
type Span = Diagnostics.Span
type Spec = Parser.Spec
type Type = Parser.Type
type TypeDeclaration = Parser.TypeDeclaration

local DEFAULTS: { [string]: any } = {
	runtime = "ReplicatedStorage.Packages.Volt",
	casing = "camel",
	writeValidation = true,
	manualReplication = false,
	flush = 1,
	maxPacket = 8192,
	maxPacketsPerSecond = 240,
	unreliableBudget = 900,
	queue = 64,
	rate = 120,
	functionRate = 60,
	timeout = 10,
	yield = "coroutine",
}

-- Every numeric option and key must be positive, and all but timeout whole
local NUMERIC: { { key: string, integer: boolean } } = {
	{ key = "flush", integer = true },
	{ key = "maxPacket", integer = true },
	{ key = "maxPacketsPerSecond", integer = true },
	{ key = "unreliableBudget", integer = true },
	{ key = "queue", integer = true },
	{ key = "rate", integer = true },
	{ key = "functionRate", integer = true },
	{ key = "timeout", integer = false },
}

local REQUIRED: { string } = { "clientOutput", "serverOutput" }
local KINDS: { [string]: string } = { event = "an event", ["function"] = "a function", namespace = "a namespace" }

-- Where a diagnostic about the file as a whole points
local FILE_START: Span = { start = 1, finish = 1 }

--[[
    Resolves a parsed file in place: options and message keys take their
    defaults, every declaration gets its full path, every reference its
    target and every named type its reference count
--]]

function Resolve.file(file: File, diagnostics: Diagnostics)
	local self = setmetatable({
		_diagnostics = diagnostics,
		_names = {} :: { [string]: Declaration },
		_state = {} :: { [TypeDeclaration]: string }, -- Cycle search: visiting or done
		_promise = nil :: Span?, -- What first asked for a promise yield
	}, Resolve)

	self:options(file.options, diagnostics.source.path)
	self:declare(file.declarations, "")
	self:bind(file.declarations, "", file.options)
	self:cycles(file.declarations)

	if self._promise and file.options.promise == nil then
		self._diagnostics:error(
			"V3004",
			"missing option promise; a promise yield needs the library's path",
			self._promise
		)
	end
end

--[[
    Checks the options that must be present and positive, then fills in
    every default; the scope defaults to the schema file's own name
--]]

function Resolve:options(options: Options, path: string)
	for _, key: string in REQUIRED do
		if options[key] == nil then
			self._diagnostics:error("V3004", `missing option {key}`, FILE_START)
		end
	end

	self:positive(options)

	for _, spec: Spec in Parser.OPTIONS do
		if options[spec.key] == nil then
			options[spec.key] = DEFAULTS[spec.key]
		end
	end

	options.scope = options.scope or path:match("([^/\\]+)%.volt$") or path

	if options.yield == "promise" then
		self._promise = options.spans.yield
	end
end

--[[
    Reports a numeric key that is zero, negative or, where a whole number
    is needed, fractional. A key the target does not carry is skipped
--]]

function Resolve:positive(target: { [string]: any })
	for _, entry: { key: string, integer: boolean } in NUMERIC do
		local value: any = target[entry.key]

		if typeof(value) == "number" and (value <= 0 or (entry.integer and value % 1 ~= 0)) then
			local wanted: string = entry.integer and "integer" or "number"
			self._diagnostics:error(
				"V3005",
				`{entry.key} must be a positive {wanted}, got {value}`,
				target.spans[entry.key]
			)
		end
	end
end

--[[
    Records every declaration under its full path, so a forward reference
    resolves, and keeps the first of two declarations with the same path
--]]

function Resolve:declare(declarations: { Declaration }, prefix: string)
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
    Binds the references inside every declaration and gives each message
    the defaults its keys did not set, after checking the keys it did
--]]

function Resolve:bind(declarations: { Declaration }, prefix: string, options: Options)
	for _, declaration: Declaration in declarations do
		if declaration.kind == "type" then
			self:type(declaration.type, prefix)
		elseif declaration.kind == "namespace" then
			self:bind(declaration.declarations, declaration.path :: string, options)
		elseif declaration.kind == "event" then
			self:positive(declaration)

			if declaration.from == "Server" and declaration.spans.rate then
				local message: string =
					"rate on a Server event has no effect; only client-to-server messages are limited"
				self._diagnostics:warn("V3006", message, declaration.spans.rate)
			end

			declaration.queue = declaration.queue or options.queue
			declaration.rate = declaration.rate or options.rate

			if declaration.data then
				self:type(declaration.data, prefix)
			end
		else
			self:positive(declaration)

			declaration.timeout = declaration.timeout or options.timeout
			declaration.rate = declaration.rate or options.functionRate
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
    Binds every reference inside a type to the named type it reaches from
    the namespace it is written in, and counts the reference on its target
--]]

function Resolve:type(node: Type | Pack, prefix: string)
	if node.kind == "reference" then
		local found: Declaration? = self:lookup(prefix, node.name)

		if not found then
			self._diagnostics:error("V3001", `unknown type "{node.name}"`, node)
		elseif found.kind ~= "type" then
			self._diagnostics:error("V3001", `"{node.name}" is {KINDS[found.kind]}, not a type`, node)
		else
			node.target = found
			found.references = (found.references :: number) + 1
		end

		return
	end

	for _, child: Type in Parser.children(node) do
		self:type(child, prefix)
	end
end

--[[
    Finds a name from inside a namespace: the namespace's own declarations
    first, then each enclosing namespace's, then the top level, so a name
    written with a namespace prefix reaches into any namespace from anywhere
--]]

function Resolve:lookup(prefix: string, name: string): Declaration?
	local scope: string = prefix

	while true do
		local found: Declaration? = self._names[scope == "" and name or `{scope}.{name}`]

		if found or scope == "" then
			return found
		end

		scope = scope:match("^(.*)%.[^.]*$") or ""
	end
end

--[[
    Reports every named type that contains itself, once per cycle, at the
    reference that closes it
--]]

function Resolve:cycles(declarations: { Declaration })
	for _, declaration: Declaration in declarations do
		if declaration.kind == "type" and not self._state[declaration] then
			self:visit(declaration)
		elseif declaration.kind == "namespace" then
			self:cycles(declaration.declarations)
		end
	end
end

function Resolve:visit(declaration: TypeDeclaration)
	self._state[declaration] = "visiting"
	self:follow(declaration.type)
	self._state[declaration] = "done"
end

function Resolve:follow(node: Type)
	if node.kind == "reference" then
		local target: TypeDeclaration? = node.target

		if target and self._state[target] == "visiting" then
			local message: string = `"{target.path}" contains itself; recursive types are not supported in this version`
			self._diagnostics:error("V3003", message, node)
		elseif target and not self._state[target] then
			self:visit(target)
		end

		return
	end

	for _, child: Type in Parser.children(node) do
		self:follow(child)
	end
end

return Resolve
