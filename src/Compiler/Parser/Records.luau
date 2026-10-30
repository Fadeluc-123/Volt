--[[
    The record grammar, merged onto the parser class: events and functions,
    each a brace-delimited list of key: value entries checked against a
    shape of specs, as the file's options are, reporting unknown, duplicate,
    missing and wrongly shaped keys with the span of each; a channel; and
    the attributes in front of a declaration, checked by rows
--]]

--!strict
local Records = {}

local Attributes = require("../Config/Attributes")
local Lexer = require("../Lexer")
local Options = require("../Config/Options")
local Schema = require("../Config/Types/Schema")
local Types = require("../Config/Types/Parser")

type Attribute = Attributes.Attribute
type Declaration = Schema.Declaration
type Parser = Types.Parser
type SchemaAttributes = Schema.Attributes
type Span = Schema.Span
type Spec = Options.Spec
type Token = Lexer.Token
type Written = Types.Written

local KINDS: { [string]: string } = {
	number = "a number",
	string = "a string",
	name = "a name",
	boolean = "true or false",
}

-- How each kind of declaration an attribute may apply to reads in a message
local DECLARATIONS: { [string]: string } = {
	type = "a type, struct or enum",
	event = "an event",
	namespace = "a namespace",
	option = "an option",

	["function"] = "a function",
}

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

local function rowOf(name: string): Attribute?
	for _, row: Attribute in Attributes do
		if row.name == name then
			return row
		end
	end
	return nil
end

local function namesOf(): string
	local names: { string } = {}
	for _, row: Attribute in Attributes do
		table.insert(names, `@{row.name}`)
	end
	return table.concat(names, ", ")
end

--[[
    Parses an event or a function: the keyword, the name and a record whose
    keys are checked against the shape
--]]

function Records.message(self: Parser, shape: { Spec }): Declaration
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

--[[
    Parses a channel: the name channel, which opens a declaration only when
    a name follows it, so a field, parameter or type may still be named
    channel, and the channel's own name
--]]

function Records.channel(self: Parser): Declaration
	self:consume()

	local name: Token = self:name()
	return { kind = "channel", name = name.value, start = name.start, finish = name.finish }
end

--[[
    Parses a brace-delimited record of key: value entries into the target,
    checking every key against the shape, then reports the keys the shape
    requires that never appeared, all at the record's name
--]]

function Records.record(self: Parser, target: { [string]: any }, shape: { Spec }, label: string)
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

function Records.entry(
	self: Parser,
	target: { [string]: any },
	shape: { Spec },
	key: Token,
	label: string,
	close: string?
)
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

function Records.value(self: Parser, spec: Spec, key: string): any
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

	local found: string = self:describe(token)
	return self:fail("V2005", `expected {expectation(spec)} for key "{key}", got {found}`, token)
end

--[[
    Reads the attributes in front of a declaration, each an @ and a name
    with a number in parentheses straight after it when it has one, in
    source order. A repeat is reported and dropped; each one spans its @
    through what closes it. Whether it may take the number waits for attach
--]]

function Records.attributes(self: Parser): { Written }
	local found: { Written } = {}
	local seen: { [string]: boolean } = {}

	while self:at("@") do
		local at: Token = self:consume()
		local name: Token = self:expect("name")
		local argument: number? = nil

		if self:at("(") then
			self:consume()

			local token: Token = self:peek()
			if token.kind ~= "number" then
				self:fail("V2005", `expected a number for "@{name.value}", got {self:describe(token)}`, token)
			end

			argument = tonumber(self:consume().value)
			self:expect("punctuation", ")")
		end

		local attribute: Written =
			{ name = name.value, argument = argument, start = at.start, finish = self:previous().finish }

		if seen[name.value] then
			self._diagnostics:error("V2002", `duplicate attribute "@{name.value}"`, attribute)
		else
			seen[name.value] = true
			table.insert(found, attribute)
		end
	end

	return found
end

--[[
    Checks the attributes read in front of a declaration against their
    rows once its kind is known, reporting one that is no row, one the
    declaration cannot carry and an argument its row does not fit, and
    returns the set of those that apply and where each was written
--]]

function Records.attach(
	self: Parser,
	found: { Written },
	kind: string,
	name: string,
	export: boolean
): (SchemaAttributes?, { [string]: Span }?)
	local applied: SchemaAttributes = {}
	local spans: { [string]: Span } = {}

	for _, attribute: Written in found do
		local row: Attribute? = rowOf(attribute.name)

		if not row then
			local message: string = `unknown attribute "@{attribute.name}"; attributes are {namesOf()}`
			self._diagnostics:error("V2011", message, attribute)
		elseif not table.find(row.kinds, kind) then
			local kinds: { string } = {}
			for _, allowed: string in row.kinds do
				table.insert(kinds, DECLARATIONS[allowed])
			end

			local message: string = `"@{row.name}" applies to {table.concat(kinds, ", ")}, not to {kind} {name}`
			self._diagnostics:error("V2012", message, attribute)
		elseif export and not row.exported then
			self._diagnostics:error("V2012", `an exported type cannot be @{row.name}`, attribute)
		elseif row.argument and attribute.argument == nil then
			local message: string = `"@{row.name}" takes a number in parentheses, such as @{row.name}(4)`
			self._diagnostics:error("V2005", message, attribute)
		elseif not row.argument and attribute.argument ~= nil then
			self._diagnostics:error("V2005", `"@{row.name}" takes no argument`, attribute)
		else
			applied[row.name] = attribute.argument or true
			spans[row.name] = attribute
		end
	end

	-- A declaration with no attribute that applies carries no set at all
	if next(applied) == nil then
		return nil, nil
	end

	return applied, spans
end

return Records
