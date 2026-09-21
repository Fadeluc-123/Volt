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
local Options = require("./Config/Options")
local Parser = require("./Parser")
local Schema = require("./Config/Types/Schema")

type Declaration = Schema.Declaration
type Diagnostics = Diagnostics.Diagnostics
type File = Schema.File
type Options = Schema.Options
type Pack = Schema.Pack
type Span = Diagnostics.Span
type Spec = Options.Spec
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration

local KINDS: { [string]: string } = { event = "an event", ["function"] = "a function", namespace = "a namespace" }

-- Where a diagnostic about the file as a whole points
local FILE_START: Span = { start = 1, finish = 1 }

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
    Reports the options that must be present, fills in every default and
    checks the numbers; the scope defaults to the schema file's own name
--]]

function Resolve:options(options: Options, path: string)
	for _, spec: Spec in Options.file do
		if options[spec.key] ~= nil then
			continue
		elseif spec.required then
			self._diagnostics:error("V3004", `missing option {spec.key}`, FILE_START)
		end

		options[spec.key] = spec.default
	end

	self:positive(options, Options.file)

	options.scope = options.scope or path:match("([^/\\]+)%.volt$") or path

	if options.yield == "promise" then
		self._promise = options.spans.yield
	end
end

--[[
    Reports a numeric key that is zero, negative or, where a whole number
    is needed, fractional. A key the target does not carry is skipped
--]]

function Resolve:positive(target: { [string]: any }, shape: { Spec })
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
			self:positive(declaration, Options.event)

			if declaration.from == "Server" and declaration.spans.rate then
				local message: string =
					"rate on a Server event has no effect; only client-to-server messages are limited"
				self._diagnostics:warn("V3006", message, declaration.spans.rate)
			end

			defaults(declaration, Options.event, options)

			if declaration.data then
				self:type(declaration.data, prefix)
			end
		else
			self:positive(declaration, Options["function"])
			defaults(declaration, Options["function"], options)

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
