--[[
    Turns a schema's tokens into declarations by recursive descent over one
    token of lookahead. Every node carries a span, a record reports its
    missing, duplicate and unknown keys together, and a syntax error
    abandons the declaration and resumes at the next one, so one run shows
    every problem in the file
--]]

--!strict
local Parser = {} :: any
Parser.__index = Parser

local Diagnostics = require("./Diagnostics")
local Lexer = require("./Lexer")

type Diagnostics = Diagnostics.Diagnostics
type Span = Diagnostics.Span
type Token = Lexer.Token

export type Range = { min: number?, max: number?, start: number, finish: number }
export type Field = { name: string, type: Type, start: number, finish: number }
export type Variant = { name: string, fields: { Field }?, start: number, finish: number }
export type Pack = { kind: "pack", parameters: { Field }, start: number, finish: number }
export type Roblox = {
	kind: "roblox",
	name: string,
	generics: { Type }?,
	class: string?,
	item: string?,
	start: number,
	finish: number,
}

export type Type =
	{ kind: "primitive", name: string, range: Range?, start: number, finish: number }
	| Roblox
	| { kind: "struct", fields: { Field }, start: number, finish: number }
	| { kind: "enum", tag: string?, variants: { Variant }, start: number, finish: number }
	| { kind: "set", element: Type, range: Range?, start: number, finish: number }
	| { kind: "map", key: Type, value: Type, range: Range?, start: number, finish: number }
	| { kind: "array", element: Type, range: Range?, start: number, finish: number }
	| { kind: "optional", inner: Type, start: number, finish: number }
	| { kind: "union", members: { Type }, start: number, finish: number }
	| { kind: "reference", name: string, start: number, finish: number }

export type TypeDeclaration = {
	kind: "type",
	name: string,
	export: boolean,
	type: Type,
	start: number,
	finish: number,
}

export type Event = {
	kind: "event",
	name: string,
	from: string,
	type: string,
	call: string,
	data: (Type | Pack)?,
	queue: number?,
	rate: (number | string)?,
	spans: { [string]: Span },
	start: number,
	finish: number,
}

export type Function = {
	kind: "function",
	name: string,
	data: (Type | Pack)?,
	["return"]: (Type | Pack)?,
	yield: string?,
	timeout: number?,
	rate: (number | string)?,
	spans: { [string]: Span },
	start: number,
	finish: number,
}

export type Namespace = {
	kind: "namespace",
	name: string,
	declarations: { Declaration },
	start: number,
	finish: number,
}

export type Declaration = TypeDeclaration | Event | Function | Namespace

export type Options = {
	clientOutput: string?,
	serverOutput: string?,
	typesOutput: string?,
	runtime: string?,
	scope: string?,
	casing: string?,
	writeValidation: boolean?,
	manualReplication: boolean?,
	flush: number?,
	maxPacket: number?,
	maxPacketsPerSecond: number?,
	unreliableBudget: number?,
	queue: number?,
	rate: (number | string)?,
	functionRate: (number | string)?,
	timeout: number?,
	yield: string?,
	promise: string?,
	spans: { [string]: Span },
}

export type File = { options: Options, declarations: { Declaration } }

type Spec = { key: string, kind: string?, values: { string }?, required: boolean? }

local DECLARATIONS: { [string]: boolean } = {
	option = true,
	export = true,
	type = true,
	struct = true,
	enum = true,
	namespace = true,
	event = true,
	["function"] = true,
}

local ROBLOX: { [string]: boolean } = {
	Vector3 = true,
	Vector2 = true,
	CFrame = true,
	AlignedCFrame = true,
	Color3 = true,
	BrickColor = true,
	DateTime = true,
	DateTimeMillis = true,
	Instance = true,
	StreamedInstance = true,
	Enum = true,
	EnumItem = true,
}

-- Consumed brackets move the depth, so a resync can tell which body it is in
local NESTING: { [string]: number } = {
	["{"] = 1,
	["("] = 1,
	["["] = 1,
	["<"] = 1,
	["}"] = -1,
	[")"] = -1,
	["]"] = -1,
	[">"] = -1,
}

-- Luau's reserved words cannot name anything the generated code spells out
local RESERVED: { [string]: boolean } = {}
local LUAU_WORDS: string =
	"and break do else elseif end false for function if in local nil not or repeat return then true until while"

for word: string in LUAU_WORDS:gmatch("%a+") do
	RESERVED[word] = true
end

local KINDS: { [string]: string } = {
	number = "a number",
	string = "a string",
	name = "a name",
	boolean = "true or false",
}

local RATE: { string } = { "unlimited" }

--[[
	Shapes are arrays so keys list and report in declaration order
--]]

local OPTIONS: { Spec } = {
	{ key = "clientOutput", kind = "string" },
	{ key = "serverOutput", kind = "string" },
	{ key = "typesOutput", kind = "string" },
	{ key = "runtime", kind = "string" },
	{ key = "scope", kind = "name" },
	{ key = "casing", values = { "camel", "pascal", "snake" } },
	{ key = "writeValidation", kind = "boolean" },
	{ key = "manualReplication", kind = "boolean" },
	{ key = "flush", kind = "number" },
	{ key = "maxPacket", kind = "number" },
	{ key = "maxPacketsPerSecond", kind = "number" },
	{ key = "unreliableBudget", kind = "number" },
	{ key = "queue", kind = "number" },
	{ key = "rate", kind = "number", values = RATE },
	{ key = "functionRate", kind = "number", values = RATE },
	{ key = "timeout", kind = "number" },
	{ key = "yield", values = { "coroutine", "promise" } },
	{ key = "promise", kind = "string" },
}

local EVENT: { Spec } = {
	{ key = "from", values = { "Client", "Server", "Both" }, required = true },
	{ key = "type", values = { "Reliable", "Unreliable" }, required = true },
	{ key = "call", values = { "SingleSync", "SingleAsync", "ManySync", "ManyAsync", "Polling" }, required = true },
	{ key = "data", kind = "data" },
	{ key = "queue", kind = "number" },
	{ key = "rate", kind = "number", values = RATE },
}

local FUNCTION: { Spec } = {
	{ key = "data", kind = "data" },
	{ key = "return", kind = "data" },
	{ key = "yield", values = { "Coroutine", "Promise" } },
	{ key = "timeout", kind = "number" },
	{ key = "rate", kind = "number", values = RATE },
}

-- Thrown to abandon a declaration after its error is reported; nothing else is ever thrown on purpose
local ABANDONED: { nil } = {}

--[[
    How a token reads in a message
--]]

local function describe(token: Token): string
	return token.kind == "eof" and "end of file"
		or token.kind == "string" and `string "{token.value}"`
		or `"{token.value}"`
end

--[[
    What a spec accepts, as a message would say it
--]]

local function expectation(spec: Spec): string
	local parts: { string } = {}
	if spec.kind then
		table.insert(parts, KINDS[spec.kind])
	end
	if spec.values then
		table.insert(parts, #spec.values == 1 and spec.values[1] or `one of {table.concat(spec.values, ", ")}`)
	end
	return table.concat(parts, " or ")
end

local function specOf(shape: { Spec }, key: string): Spec?
	for _, spec: Spec in shape do
		if spec.key == key then
			return spec
		end
	end

	return nil
end

local function keysOf(shape: { Spec }): string
	local keys: { string } = {}
	for _, spec: Spec in shape do
		table.insert(keys, spec.key)
	end
	return table.concat(keys, ", ")
end

--[[
    Parses a whole token list into the file's options and declarations
--]]

function Parser.parse(tokens: { Token }, diagnostics: Diagnostics): File
	local self = setmetatable({
		_tokens = tokens,
		_diagnostics = diagnostics,
		_index = 1, -- The lookahead token
		_depth = 0, -- Brackets opened and not yet closed
		_options = { spans = {} },
		_declared = false, -- Set by the first declaration, after which an option is out of place
	}, Parser)

	return { options = self._options, declarations = self:declarations(nil) }
end

--[[
    Parses declarations up to the closing brace or the end of the file. A
    declaration that fails is abandoned and the parse resumes at the next
    one, so everything after a broken declaration is still checked
--]]

function Parser:declarations(close: string?): { Declaration }
	local declarations: { Declaration } = {}
	local depth: number = self._depth

	while self:peek().kind ~= "eof" and not (close and self:at(close)) do
		local before: number = self._index
		local ok: boolean, result: any = pcall(self.declaration, self)

		if ok then
			if result then
				table.insert(declarations, result)
			end
		elseif result == ABANDONED then
			-- Always move past the failing token, or a declaration that consumed nothing would loop forever
			if self._index == before then
				self:consume()
			end

			self:synchronise(depth, close)
		else
			error(result, 0)
		end
	end

	return declarations
end

--[[
    Skips to the next declaration keyword, or to the brace that closes the
    enclosing namespace, whichever comes first. A keyword counts only when
    a name follows it, which is what tells struct Stack from struct {
--]]

function Parser:synchronise(depth: number, close: string?)
	while self:peek().kind ~= "eof" do
		local token: Token = self:peek()
		local following: Token = self:peek(1)
		local declares: boolean = token.kind == "keyword"
			and DECLARATIONS[token.value] == true
			and (token.value == "export" or following.kind == "name")

		if declares then
			self._depth = depth -- Whatever body was left open is abandoned with its declaration
			return
		end

		if close and self._depth == depth and self:at(close) then
			return
		end

		self:consume()
	end
end

--[[
    Parses one declaration. Options are collected into the file's option
    table rather than returned, and reported once a declaration has gone
    before them
--]]

function Parser:declaration(): Declaration?
	local token: Token = self:peek()

	if self:at("option") then
		if self._declared then
			local message: string = `option "{self:peek(1).value}" comes after a declaration; options come first`
			self._diagnostics:error("V2009", message, token)
		end

		self:option()
		return nil
	end

	self._declared = true

	if self:at("export") or self:at("type") or self:at("struct") or self:at("enum") then
		return self:typeDeclaration()
	elseif self:at("event") then
		return self:message(EVENT)
	elseif self:at("function") then
		return self:message(FUNCTION)
	elseif self:at("namespace") then
		return self:namespace()
	end

	return self:fail("V2001", `expected a declaration, got {describe(token)}`, token)
end

function Parser:option()
	self:consume()

	local key: Token = self:key()
	self:expect("punctuation", "=")
	self:entry(self._options, OPTIONS, key, "the options", nil)
end

--[[
    Parses a named type in any of its three spellings. A struct or enum
    declaration is the same node as a type declaration of that inline type,
    so later stages see one kind of named type
--]]

function Parser:typeDeclaration(): Declaration
	local export: boolean = self:at("export")
	if export then
		self:consume()
	end

	local keyword: Token = self:peek()
	if not (self:at("type") or self:at("struct") or self:at("enum")) then
		self:fail("V2001", `expected "type", "struct" or "enum" after "export", got {describe(keyword)}`, keyword)
	end

	self:consume()

	local name: Token = self:name()
	local declared: Type

	if keyword.value == "struct" then
		declared = self:struct(keyword.start)
	elseif keyword.value == "enum" then
		declared = self:enum(keyword.start)
	else
		if self:at("<") then
			self:fail("V2008", "generic types are not supported in this version", self:peek())
		end

		self:expect("punctuation", "=")
		declared = self:type()
	end

	return {
		kind = "type",
		name = name.value,
		export = export,
		type = declared,
		start = name.start,
		finish = name.finish,
	}
end

--[[
    Parses an event or a function: the keyword, the name and a record whose
    keys are checked against the shape
--]]

function Parser:message(shape: { Spec }): Declaration
	local keyword: Token = self:consume()
	local name: Token = self:name()
	local node = {
		kind = keyword.value,
		name = name.value,
		spans = {},
		start = name.start,
		finish = name.finish,
	} :: any

	self:record(node, shape, `{keyword.value} {name.value}`)
	return node
end

function Parser:namespace(): Declaration
	self:consume()

	local name: Token = self:name()
	self:expect("punctuation", "{")

	local declarations: { Declaration } = self:declarations("}")
	self:expect("punctuation", "}")

	return {
		kind = "namespace",
		name = name.value,
		declarations = declarations,
		start = name.start,
		finish = name.finish,
	}
end

--[[
    Parses a brace-delimited record of key: value entries into the target,
    checking every key against the shape, then reports the keys the shape
    requires that never appeared, all at the record's name
--]]

function Parser:record(target: { [string]: any }, shape: { Spec }, label: string)
	self:expect("punctuation", "{")
	self:list("}", function ()
		local key: Token = self:key()

		self:expect("punctuation", ":")
		self:entry(target, shape, key, label, "}")
	end)

	for _, spec: Spec in shape do
		if spec.required and target.spans[spec.key] == nil then
			self._diagnostics:error("V2004", `missing key "{spec.key}" in {label}`, target)
		end
	end
end

--[[
    Parses one key's value into the target. An unknown key is reported and
    its value skipped, a duplicate is reported and its value dropped, and a
    value of the wrong shape abandons the declaration
--]]

function Parser:entry(target: { [string]: any }, shape: { Spec }, key: Token, label: string, close: string?)
	local spec: Spec? = specOf(shape, key.value)
	if not spec then
		self._diagnostics:error("V2003", `unknown key "{key.value}" in {label}; keys are {keysOf(shape)}`, key)
		self:skip(close)
		return
	end

	local value: any = self:value(spec, key.value)
	if target.spans[key.value] then
		return self._diagnostics:error("V2002", `duplicate key "{key.value}" in {label}`, key)
	end

	target[key.value] = value
	target.spans[key.value] = key
end

--[[
    Parses a value of the shape the spec asks for: a name from a fixed
    list, a number, a string, a bare name, true or false, or a type or
    parameter pack where data and return go
--]]

function Parser:value(spec: Spec, key: string): any
	local token: Token = self:peek()

	if spec.kind == "data" then
		return self:at("(") and self:pack() or self:type()
	elseif spec.values and token.kind == "name" and table.find(spec.values, token.value) then
		return self:consume().value
	elseif spec.kind == "number" and token.kind == "number" then
		return tonumber(self:consume().value)
	elseif spec.kind == "string" and token.kind == "string" then
		return self:consume().value
	elseif spec.kind == "name" and token.kind == "name" then
		return self:consume().value
	elseif spec.kind == "boolean" and (self:at("true") or self:at("false")) then
		return self:consume().value == "true"
	end

	return self:fail("V2005", `expected {expectation(spec)} for key "{key}", got {describe(token)}`, token)
end

--[[
    Parses a full type: members joined by | and an optional ? outside them
--]]

function Parser:type(): Type
	local start: number = self:peek().start
	local members: { Type } = { self:postfix() }

	while self:at("|") do
		self:consume()
		table.insert(members, self:postfix())
	end

	local result: Type = members[1]
	if #members > 1 then
		result = { kind = "union", members = members, start = start, finish = self:previous().finish }
	end

	if self:at("?") then
		self:consume()
		return { kind = "optional", inner = result, start = start, finish = self:previous().finish }
	end

	return result
end

--[[
    An atom followed by any number of array suffixes
--]]

function Parser:postfix(): Type
	local result: Type = self:atom()

	while self:at("[") do
		self:consume()

		local range: Range? = nil
		if not self:at("]") then
			range = self:range()
		end
		self:expect("punctuation", "]")

		result = {
			kind = "array",
			element = result,
			range = range,
			start = result.start,
			finish = self:previous().finish,
		}
	end

	return result
end

--[[
    The type forms that start with a distinct token: a primitive with its
    bounds, an inline struct or enum, a set, a map, a Roblox type or a
    reference to a named type
--]]

function Parser:atom(): Type
	local token: Token = self:peek()

	if token.kind == "primitive" then
		self:consume()
		return {
			kind = "primitive",
			name = token.value,
			range = self:bounds(),
			start = token.start,
			finish = self:previous().finish,
		}
	elseif self:at("struct") then
		self:consume()
		return self:struct(token.start)
	elseif self:at("enum") then
		self:consume()
		return self:enum(token.start)
	elseif self:at("set") then
		self:consume()
		self:expect("punctuation", "<")

		local element: Type = self:type()
		self:expect("punctuation", ">")

		return {
			kind = "set",
			element = element,
			range = self:bounds(),
			start = token.start,
			finish = self:previous().finish,
		}
	elseif self:at("{") then
		self:consume()
		self:expect("punctuation", "[")

		local key: Type = self:type()
		self:expect("punctuation", "]")
		self:expect("punctuation", ":")

		local value: Type = self:type()
		self:expect("punctuation", "}")

		return {
			kind = "map",
			key = key,
			value = value,
			range = self:bounds(),
			start = token.start,
			finish = self:previous().finish,
		}
	elseif token.kind == "string" then
		self:fail("V2008", "literal types are not supported in this version", token)
	elseif token.kind ~= "name" then
		self:fail("V2001", `expected a type, got {describe(token)}`, token)
	end

	self:consume()

	if ROBLOX[token.value] then
		return self:roblox(token)
	end

	local path: { string } = { token.value }
	while self:at(".") do
		self:consume()
		table.insert(path, self:expect("name").value)
	end

	return {
		kind = "reference",
		name = table.concat(path, "."),
		start = token.start,
		finish = self:previous().finish,
	}
end

--[[
    A Roblox type and whatever follows its name: the item of an Enum, the
    class of an Instance, or the generic arguments of a vector or CFrame.
    Which of those the type accepts is checked in analysis
--]]

function Parser:roblox(token: Token): Type
	local node: Roblox = {
		kind = "roblox",
		name = token.value,
		start = token.start,
		finish = token.finish,
	}

	if token.value == "Enum" then
		self:expect("punctuation", ".")
		node.item = self:expect("name").value
	elseif self:at("(") then
		self:consume()
		node.class = self:expect("name").value
		self:expect("punctuation", ")")
	elseif self:at("<") then
		self:consume()
		node.generics = { self:type() }

		while self:at(",") do
			self:consume()
			table.insert(node.generics :: { Type }, self:type())
		end

		self:expect("punctuation", ">")
	end

	node.finish = self:previous().finish
	return node
end

function Parser:struct(start: number): Type
	local fields: { Field } = self:fields("{", "}")
	return {
		kind = "struct",
		fields = fields,
		start = start,
		finish = self:previous().finish,
	}
end

--[[
    An enum body, tagged when a string precedes it. Only a tagged enum's
    variants may carry fields, because the tag is what names the variant
    inside the value
--]]

function Parser:enum(start: number): Type
	local tag: Token? = self:peek().kind == "string" and self:consume() or nil
	local variants: { Variant } = {}
	local seen: { [string]: boolean } = {}

	if tag and (RESERVED[tag.value] or not tag.value:match("^[%a_][%w_]*$")) then
		self._diagnostics:error("V2006", `tag "{tag.value}" is not a valid Luau name`, tag)
	end

	self:expect("punctuation", "{")
	self:list("}", function ()
		local name: Token = self:name()
		local fields: { Field }? = nil

		if self:at("{") then
			if not tag then
				self._diagnostics:error("V2007", `variant "{name.value}" has fields but the enum has no tag`, name)
			end

			fields = self:fields("{", "}")
		end

		if seen[name.value] then
			return self._diagnostics:error("V2002", `duplicate variant "{name.value}"`, name)
		end

		seen[name.value] = true

		table.insert(variants, {
			name = name.value,
			fields = fields,
			start = name.start,
			finish = self:previous().finish,
		})
	end)

	return {
		kind = "enum",
		tag = tag and tag.value or nil,
		variants = variants,
		start = start,
		finish = self:previous().finish,
	}
end

--[[
    A bracketed list of name: type fields, which is a struct body in braces
    and a parameter pack in parentheses
--]]

function Parser:fields(open: string, close: string): { Field }
	local fields: { Field } = {}
	local seen: { [string]: boolean } = {}

	self:expect("punctuation", open)
	self:list(close, function ()
		if self:at("..") then
			self:fail("V2008", "struct spread is not supported in this version", self:peek())
		end

		local name: Token = self:name()
		self:expect("punctuation", ":")

		local fieldType: Type = self:type()

		if seen[name.value] then
			return self._diagnostics:error("V2002", `duplicate field "{name.value}"`, name)
		end

		seen[name.value] = true

		table.insert(fields, { name = name.value, type = fieldType, start = name.start, finish = fieldType.finish })
	end)

	return fields
end

function Parser:pack(): Pack
	local start: number = self:peek().start
	local parameters: { Field } = self:fields("(", ")")

	return {
		kind = "pack",
		parameters = parameters,
		start = start,
		finish = self:previous().finish,
	}
end

--[[
    The optional parenthesised range after a primitive, a map or a set
--]]

function Parser:bounds(): Range?
	if not self:at("(") then
		return nil
	end

	self:consume()

	local range: Range = self:range()
	self:expect("punctuation", ")")

	return range
end

--[[
    A range in any of its four forms: both ends, either end alone, or one
    number meaning exactly that
--]]

function Parser:range(): Range
	local first: Token = self:peek()
	local min: number? = nil
	local max: number? = nil

	if first.kind == "number" then
		min = tonumber(self:consume().value)
	end

	if self:at("..") then
		self:consume()

		if self:peek().kind == "number" then
			max = tonumber(self:consume().value)
		end
	else
		max = min
	end

	if min == nil and max == nil then
		self:fail("V2001", `expected a range, got {describe(first)}`, first)
	end

	return {
		min = min,
		max = max,
		start = first.start,
		finish = self:previous().finish,
	}
end

--[[
    Parses comma-separated items up to the closing bracket, allowing a
    trailing comma, and consumes the bracket
--]]

function Parser:list(close: string, item: () -> ())
	while not self:at(close) and self:peek().kind ~= "eof" do
		item()

		if not self:at(",") then
			break
		end

		self:consume()
	end

	self:expect("punctuation", close)
end

--[[
    The token at the cursor, or the one a given distance ahead. Past the
    end it is always the eof token
--]]

function Parser:peek(ahead: number?): Token
	return self._tokens[math.min(self._index + (ahead or 0), #self._tokens)]
end

--[[
    Whether the token at the cursor is the given keyword, name or
    punctuation. A string token never matches, whatever it holds
--]]

function Parser:at(value: string): boolean
	local token: Token = self:peek()
	return token.kind ~= "string" and token.value == value
end

--[[
    Advances past the token at the cursor and returns it. The eof token is
    never passed, so every loop over the cursor ends
--]]

function Parser:consume(): Token
	local token: Token = self:peek()
	if token.kind ~= "eof" then
		self._index += 1
	end
	if token.kind == "punctuation" then
		self._depth += NESTING[token.value] or 0
	end
	return token
end

function Parser:previous(): Token
	return self._tokens[self._index - 1]
end

--[[
    Consumes the token at the cursor if it has the kind, and the value when
    one is given, or abandons the declaration
--]]

function Parser:expect(kind: Lexer.Kind, value: string?): Token
	local token: Token = self:peek()
	if token.kind ~= kind or (value ~= nil and token.value ~= value) then
		local wanted: string = value and `"{value}"` or `a {kind}`
		self:fail("V2001", `expected {wanted}, got {describe(token)}`, token)
	end
	return self:consume()
end

--[[
    A record key: any name, including the keywords the schema also uses as
    keys, such as type
--]]

function Parser:key(): Token
	local token: Token = self:peek()
	if token.kind ~= "name" and token.kind ~= "keyword" then
		self:fail("V2001", `expected a name, got {describe(token)}`, token)
	end
	return self:consume()
end

--[[
    A name that the generated code will spell out as a Luau identifier, so
    a reserved word is reported, though the parse carries on
--]]

function Parser:name(): Token
	local token: Token = self:key()
	if RESERVED[token.value] then
		self._diagnostics:error("V2006", `"{token.value}" is a Luau reserved word and cannot be a name`, token)
	end
	return token
end

--[[
    Skips a value nobody wants: one token for an option, or everything up
    to the next comma or closing brace at this depth inside a record
--]]

function Parser:skip(close: string?)
	local depth: number = self._depth
	repeat
		self:consume()
	until self:peek().kind == "eof" or close == nil or (self._depth == depth and (self:at(",") or self:at(close)))
end

--[[
    Reports an error and abandons the declaration being parsed; the
    declarations loop catches it and resumes at the next one
--]]

function Parser:fail(code: string, message: string, span: Span): never
	self._diagnostics:error(code, message, span)
	error(ABANDONED, 0)
end

return Parser
