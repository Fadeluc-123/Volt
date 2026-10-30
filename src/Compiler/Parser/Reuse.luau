--[[
    The forms that let a schema write a type once and use it again, merged
    onto the parser class: a declaration's type parameters, a reference's
    type arguments and a spread entry in a struct or variant body
--]]

--!strict
local Reuse = {}

local Lexer = require("../Lexer")
local Schema = require("../Config/Types/Schema")
local Types = require("../Config/Types/Parser")

type Field = Schema.Field
type Parameter = Schema.Parameter
type Parser = Types.Parser
type Token = Lexer.Token
type Type = Schema.Type

--[[
    The type parameters after a declaration's name, each read as a name is,
    or nil when no angle bracket follows it. A parameter named twice is
    reported and the first kept
--]]

function Reuse.parameters(self: Parser): { Parameter }?
	if not self:at("<") then
		return nil
	end

	local parameters: { Parameter } = {}
	local seen: { [string]: boolean } = {}

	self:consume()

	repeat
		local name: Token = self:name()

		if seen[name.value] then
			self._diagnostics:error("V2002", `duplicate type parameter "{name.value}"`, name)
		else
			seen[name.value] = true
			table.insert(parameters, { name = name.value, start = name.start, finish = name.finish })
		end

		local more: boolean = self:at(",")
		if more then
			self:consume()
		end
	until not more or self:at(">")

	self:expect("punctuation", ">")

	return parameters
end

--[[
    The type arguments straight after a reference's path, any types at all,
    or nil when no angle bracket follows it
--]]

function Reuse.arguments(self: Parser): { Type }?
	if not self:at("<") then
		return nil
	end

	local arguments: { Type } = {}

	self:consume()

	repeat
		table.insert(arguments, self:type())

		local more: boolean = self:at(",")
		if more then
			self:consume()
		end
	until not more or self:at(">")

	self:expect("punctuation", ">")

	return arguments
end

--[[
    A spread entry: a field with no name and the reference after the .. as
    its type. A pack holds parameters, so it can spread nothing
--]]

function Reuse.spread(self: Parser, pack: boolean): Field
	local open: Token = self:peek()

	if pack then
		self:fail("V2001", "a parameter pack cannot spread a struct", open)
	end

	self:consume()

	local first: Token = self:peek()
	local reference: Type? = first.kind == "name" and self:atom() or nil

	if not reference or reference.kind ~= "reference" then
		return self:fail("V2001", `expected a struct's name after ".."`, first)
	end

	return { name = "", type = reference, spread = true, start = open.start, finish = reference.finish }
end

return Reuse
