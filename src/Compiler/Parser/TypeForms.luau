--[[
    The type forms, merged onto the parser class: a union of postfix
    types with an optional mark outside it, where an atom is a primitive
    with its bounds, an inline struct or enum, a set, a map, a Roblox type
    with what follows its name, or a reference to a named type; and the
    field lists, parameter packs and ranges those forms carry
--]]

--!strict
local TypeForms = {} :: any

local Lexer = require("../Lexer")
local Reserved = require("../Config/Reserved")
local Roblox = require("../Config/Roblox")
local Schema = require("../Config/Types/Schema")

type Field = Schema.Field
type Pack = Schema.Pack
type Range = Schema.Range
type Roblox = Schema.Roblox
type Token = Lexer.Token
type Type = Schema.Type
type Variant = Schema.Variant

--[[
    Parses a full type: members joined by | and an optional ? outside them
--]]

function TypeForms:type(): Type
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

function TypeForms:postfix(): Type
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

function TypeForms:atom(): Type
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
		self:fail("V2001", `expected a type, got {self:describe(token)}`, token)
	end

	self:consume()

	if Roblox[token.value] then
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

function TypeForms:roblox(token: Token): Type
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

function TypeForms:struct(start: number): Type
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

function TypeForms:enum(start: number): Type
	local tag: Token? = self:peek().kind == "string" and self:consume() or nil
	local variants: { Variant } = {}
	local seen: { [string]: boolean } = {}

	if tag and (Reserved.luau[tag.value] or not tag.value:match("^[%a_][%w_]*$")) then
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

function TypeForms:fields(open: string, close: string): { Field }
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

function TypeForms:pack(): Pack
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

function TypeForms:bounds(): Range?
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

function TypeForms:range(): Range
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
		self:fail("V2001", `expected a range, got {self:describe(first)}`, first)
	end

	return {
		min = min,
		max = max,
		start = first.start,
		finish = self:previous().finish,
	}
end

return TypeForms
