--[[
    Expand's last pass: a named type or instantiation whose type reaches it
    again is recursive and takes its depth, a @depth on one that is not is
    refused, and so is a recursive type with no value that ends, which a
    fixed point over the recursive types finds
--]]

--!strict
local Recursion = {}

local Diagnostics = require("./Diagnostics")
local Parser = require("./Parser")
local Schema = require("./Config/Types/Schema")
local Sizes = require("./Analyse/Sizes")
local Wire = require("./Config/Wire")

type Diagnostics = Diagnostics.Diagnostics
type Field = Schema.Field
type Pack = Schema.Pack
type Span = Diagnostics.Span
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration
type Variant = Schema.Variant

local DEFAULT_DEPTH: number = Wire.depth

local NO_END: string =
	"has no finite value: every way through it leads back to it; an optional, a collection that may be empty or another variant on the way ends it"

-- Whether a type reaches a named type through its references, walking each name once
local function reaches(node: Type | Pack, goal: TypeDeclaration, walked: { [TypeDeclaration]: boolean }): boolean
	if node.kind == "reference" then
		local target: TypeDeclaration? = node.target

		if target == goal then
			return true
		elseif not target or walked[target] then
			return false
		end

		walked[target] = true
		return reaches(target.type, goal, walked)
	end

	for _, child: Type in Parser.children(node) do
		if reaches(child, goal, walked) then
			return true
		end
	end

	return false
end

--[[
    Whether a type has a value that ends, given which recursive types have
    been found to: an optional, a collection whose least length is 0, a
    variant or member that has one, and a struct whose fields all have one
--]]

local function ends(node: Type, finite: { [TypeDeclaration]: boolean }): boolean
	local function fieldsEnd(list: { Field }): boolean
		for _, field: Field in list do
			if not ends(field.type, finite) then
				return false
			end
		end
		return true
	end

	if node.kind == "reference" then
		local target: TypeDeclaration? = node.target

		if not target then
			return true -- Already reported
		elseif target.depth then
			return finite[target] == true
		end

		return ends(target.type, finite)
	elseif node.kind == "optional" then
		return true
	elseif node.kind == "struct" then
		return fieldsEnd(node.fields)
	elseif node.kind == "enum" then
		for _, variant: Variant in node.variants do
			if fieldsEnd(variant.fields or {}) then
				return true
			end
		end
		return #node.variants == 0
	elseif node.kind == "union" then
		for _, member: Type in node.members do
			if ends(member, finite) then
				return true
			end
		end
		return false
	elseif
		(node.kind == "array" or node.kind == "set" or node.kind == "map")
		and (select(2, Sizes.lengths(node.range))) > 0
	then
		for _, child: Type in Parser.children(node) do
			if not ends(child, finite) then
				return false
			end
		end
	end

	return true
end

--[[
    Finds the recursive types among every named type that is no template,
    one search from each, gives each its depth, refuses a @depth on a type
    no search finds recursive, and refuses a recursive type with no value
    that ends, at its name or the reference that first named an instantiation
--]]

function Recursion.check(diagnostics: Diagnostics, named: { TypeDeclaration })
	local recursive: { TypeDeclaration } = {}
	local deep: { [TypeDeclaration]: boolean } = {}

	for _, declaration: TypeDeclaration in named do
		if reaches(declaration.type, declaration, {}) then
			local attributes: Schema.Attributes = declaration.attributes or {}
			local depth: any = attributes.depth

			declaration.depth = depth or DEFAULT_DEPTH
			deep[declaration.generic or declaration] = true
			table.insert(recursive, declaration)
		end
	end

	for _, declaration: TypeDeclaration in named do
		local origin: TypeDeclaration = declaration.generic or declaration
		local attribute: Span? = origin.spans and origin.spans.depth or nil

		if attribute and not deep[origin] then
			local message: string = `"{origin.path}" is not recursive, so @depth changes nothing`
			diagnostics:error("V3018", message, attribute)
		end
	end

	local finite: { [TypeDeclaration]: boolean } = {}
	local changed: boolean = true

	while changed do
		changed = false

		for _, declaration: TypeDeclaration in recursive do
			if not finite[declaration] and ends(declaration.type, finite) then
				finite[declaration] = true
				changed = true
			end
		end
	end

	for _, declaration: TypeDeclaration in recursive do
		if not finite[declaration] then
			diagnostics:error("V3003", `"{declaration.path}" {NO_END}`, declaration)
		end
	end
end

return Recursion
