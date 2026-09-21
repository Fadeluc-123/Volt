--[[
    The record grammar, merged onto the parser class: a brace-delimited
    list of key: value entries checked against a shape of specs, which is
    how events, functions and the file's options are read, reporting
    unknown, duplicate, missing and wrongly shaped keys with the span of
    each
--]]

--!strict
local Records = {} :: any

local Lexer = require("../Lexer")
local Options = require("../Config/Options")

type Spec = Options.Spec
type Token = Lexer.Token

local KINDS: { [string]: string } = {
	number = "a number",
	string = "a string",
	name = "a name",
	boolean = "true or false",
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

--[[
    Parses a brace-delimited record of key: value entries into the target,
    checking every key against the shape, then reports the keys the shape
    requires that never appeared, all at the record's name
--]]

function Records:record(target: { [string]: any }, shape: { Spec }, label: string)
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

function Records:entry(target: { [string]: any }, shape: { Spec }, key: Token, label: string, close: string?)
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

function Records:value(spec: Spec, key: string): any
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

return Records
