--[[
    Turns a schema's tokens into declarations by recursive descent over one
    token of lookahead. Every node carries a span, and a syntax error
    abandons the declaration and resumes at the next one, so one run shows
    every problem in the file. The token, record and type form methods
    live in the sibling files and are merged onto the class here
--]]

--!strict
local Parser = {} :: any
Parser.__index = Parser

-- An init file stands for its folder, so its siblings are reached through the folder's name
local Diagnostics = require("./Diagnostics")
local Lexer = require("./Lexer")
local Options = require("./Config/Options")
local Records = require("./Parser/Records")
local Schema = require("./Config/Types/Schema")
local Source = require("./Source")
local Tokens = require("./Parser/Tokens")
local TypeForms = require("./Parser/TypeForms")

type Declaration = Schema.Declaration
type Diagnostics = Diagnostics.Diagnostics
type Field = Schema.Field
type File = Schema.File
type Options = Schema.Options
type Pack = Schema.Pack
type Source = Source.Source
type SourceFile = Source.File
type Span = Diagnostics.Span
type Spec = Options.Spec
type Token = Lexer.Token
type Type = Schema.Type
type Variant = Schema.Variant

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

-- Thrown to abandon a declaration after its error is reported; nothing else is ever thrown on purpose
local ABANDONED: { nil } = {}

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
    The option a file sets first, by where it sits, which is where an
    option in the wrong file is reported
--]]

local function firstOption(options: Options): (string?, Span?)
	local key: string?, span: Span? = nil, nil

	for _, spec: Spec in Options.file do
		local at: Span? = options.spans[spec.key]
		if at and (not span or at.start < span.start) then
			key, span = spec.key, at
		end
	end

	return key, span
end

--[[
    Lexes and parses every file of a source on its own and joins them into
    one schema. The options file is the first that sets any option, its
    declarations go first and the others' follow in the order they were
    read, and an option set in any other file is reported where it starts
--]]

function Parser.schema(source: Source, diagnostics: Diagnostics): File
	local files: { File } = {}
	local home: number? = nil

	for index: number, entry: SourceFile in source.files do
		local file: File = Parser.parse(Lexer.scan(source, diagnostics, entry), diagnostics)
		local key: string?, span: Span? = firstOption(file.options)

		-- The first file to set an option is the options file, so any later one setting one is out of place
		if span and home then
			local message: string = `option "{key}" is in a second file; options are set in {source.files[home].path}`
			diagnostics:error("V2010", message, span)
		elseif span then
			home = index
		end

		table.insert(files, file)
	end

	-- With no file setting an option the first one stands in, so a missing option is reported at its top
	local chosen: number = home or 1
	local first: File = table.remove(files, chosen) :: File
	local declarations: { Declaration } = first.declarations

	for _, file: File in files do
		table.move(file.declarations, 1, #file.declarations, #declarations + 1, declarations)
	end

	source.path = source.files[chosen].path
	source.start = source.files[chosen].start

	return { options = first.options, declarations = declarations }
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
		return self:message(Options.event)
	elseif self:at("function") then
		return self:message(Options["function"])
	elseif self:at("namespace") then
		return self:namespace()
	end

	return self:fail("V2001", `expected a declaration, got {self:describe(token)}`, token)
end

function Parser:option()
	self:consume()

	local key: Token = self:key()
	self:expect("punctuation", "=")
	self:entry(self._options, Options.file, key, "the options", nil)
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
		local found: string = self:describe(keyword)
		self:fail("V2001", `expected "type", "struct" or "enum" after "export", got {found}`, keyword)
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
    Reports an error and abandons the declaration being parsed; the
    declarations loop catches it and resumes at the next one
--]]

function Parser:fail(code: string, message: string, span: Span): never
	self._diagnostics:error(code, message, span)
	error(ABANDONED, 0)
end

--[[
    The type nodes directly inside a node, so a pass over the tree can
    recurse without knowing every shape
--]]

function Parser.children(node: Type | Pack): { Type }
	local list: { Type } = {}

	if node.kind == "struct" then
		for _, field: Field in node.fields do
			table.insert(list, field.type)
		end
	elseif node.kind == "pack" then
		for _, field: Field in node.parameters do
			table.insert(list, field.type)
		end
	elseif node.kind == "enum" then
		for _, variant: Variant in node.variants do
			for _, field: Field in (variant.fields or {}) :: { Field } do
				table.insert(list, field.type)
			end
		end
	elseif node.kind == "map" then
		return { node.key, node.value }
	elseif node.kind == "array" or node.kind == "set" then
		return { node.element }
	elseif node.kind == "optional" then
		return { node.inner }
	elseif node.kind == "union" then
		return node.members
	elseif node.kind == "roblox" then
		return node.generics or {}
	end

	return list
end

-- Each part of the grammar is parsed by the methods of one sibling file, and a name defined twice is a bug
for _, part in { Tokens, Records, TypeForms } do
	for name: string, method in part do
		assert(Parser[name] == nil, `Parser.{name} is defined twice`)
		Parser[name] = method
	end
end

return Parser
