--[[
    Expand's first pass: every spread entry in a struct or variant body,
    a generic's body included, becomes copies of the fields of the struct
    declaration it names. Holds the deep copy of a type too, which an
    instantiation makes of its generic's body
--]]

--!strict
local Spreads = {}

local Diagnostics = require("./Diagnostics")
local Parser = require("./Parser")
local Print = require("./Analyse/Print")
local Schema = require("./Config/Types/Schema")

type Diagnostics = Diagnostics.Diagnostics
type Field = Schema.Field
type Pack = Schema.Pack
type Span = Diagnostics.Span
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration
type Variant = Schema.Variant

export type State = {
	diagnostics: Diagnostics,
	spreading: { [TypeDeclaration]: string }, -- Each named type's spreads: visiting, or done
}

-- How each type that is no struct reads in a refused spread
local KINDS: { [string]: string } = {
	primitive = "a primitive",
	roblox = "a Roblox type",
	enum = "an enum",
	set = "a set",
	map = "a map",
	array = "an array",
	optional = "an optional",
	union = "a union",
	reference = "an alias",
	literal = "a literal",
}

--[[
    A deep copy of a type, each reference to a type parameter replaced by
    a copy of its argument. With no arguments, a parameter stays what it
    is, as one in a spread's argument must inside the generic it sits in
--]]

function Spreads.copy(node: Type, arguments: { Type }?): Type
	if node.kind == "reference" and node.parameter and arguments then
		return Spreads.copy(arguments[node.parameter])
	end

	local function copies(list: { Type }): { Type }
		local result: { Type } = {}
		for _, item: Type in list do
			table.insert(result, Spreads.copy(item, arguments))
		end
		return result
	end

	local function copyFields(list: { Field }): { Field }
		local result: { Field } = {}
		for _, field: Field in list do
			local clone: Field = table.clone(field)

			clone.type = Spreads.copy(field.type, arguments)
			table.insert(result, clone)
		end
		return result
	end

	local clone: any = table.clone(node)

	if node.kind == "struct" then
		clone.fields = copyFields(node.fields)
	elseif node.kind == "enum" then
		clone.variants = {}

		for _, variant: Variant in node.variants do
			local entry: Variant = table.clone(variant)

			entry.fields = variant.fields and copyFields(variant.fields) or nil
			table.insert(clone.variants, entry)
		end
	elseif node.kind == "map" then
		clone.key = Spreads.copy(node.key, arguments)
		clone.value = Spreads.copy(node.value, arguments)
	elseif node.kind == "array" or node.kind == "set" then
		clone.element = Spreads.copy(node.element, arguments)
	elseif node.kind == "optional" then
		clone.inner = Spreads.copy(node.inner, arguments)
	elseif node.kind == "union" then
		clone.members = copies(node.members)
	elseif node.kind == "roblox" and node.generics then
		clone.generics = copies(node.generics)
	elseif node.kind == "reference" and node.arguments then
		clone.arguments = copies(node.arguments)
	end

	return clone
end

-- Expands a named type's own spreads, once, so a spread of it copies fields that are all written out
function Spreads.declaration(state: State, declaration: TypeDeclaration)
	if not state.spreading[declaration] then
		state.spreading[declaration] = "visiting"
		Spreads.walk(state, declaration.type, declaration.path :: string)
		state.spreading[declaration] = "done"
	end
end

--[[
    The fields a spread entry stands for, or nil when it is refused or its
    name is already reported: copies of a struct declaration's fields, its
    own spreads expanded first and a generic's parameters replaced by the
    spread's arguments
--]]

local function spreadFields(state: State, entry: Field, owner: string): { Field }?
	local reference: any = entry.type
	local target: TypeDeclaration? = reference.target

	if reference.parameter then
		local message: string = `a spread takes a struct, and "{reference.name}" is a type parameter`
		state.diagnostics:error("V3019", message, entry)
		return nil
	elseif not target then
		return nil
	end

	local body: Type = target.type

	if body.kind ~= "struct" then
		local message: string = `a spread takes a struct, and "{target.path}" is {KINDS[body.kind]}`
		state.diagnostics:error("V3019", message, entry)
		return nil
	elseif state.spreading[target] == "visiting" then
		local through: string = target.path == owner and "" or ` through "{owner}"`
		state.diagnostics:error("V3019", `"{target.path}" spreads itself{through}`, entry)
		return nil
	end

	Spreads.declaration(state, target)

	return (Spreads.copy(body, reference.arguments) :: any).fields
end

--[[
    A struct or variant body with its spreads replaced by their fields in
    the place each is written. A field name that comes twice is reported
    at the second, wherever the two come from, and the first kept
--]]

local function body(state: State, fields: { Field }, owner: string): { Field }
	local merged: { Field } = {}
	local origins: { [string]: string } = {}

	local function add(field: Field, origin: string, at: Span)
		local first: string? = origins[field.name]

		if first then
			state.diagnostics:error("V3020", `field "{field.name}" comes twice in {owner}, {first} and {origin}`, at)
		else
			origins[field.name] = origin
			table.insert(merged, field)
		end
	end

	for _, field: Field in fields do
		-- A spread's arguments may hold a spread of their own, in an inline struct
		Spreads.walk(state, field.type, owner)

		if field.spread then
			for _, copied: Field in spreadFields(state, field, owner) or {} do
				add(copied, `from ..{Print.type(field.type)}`, field)
			end
		else
			add(field, "as written", field)
		end
	end

	return merged
end

-- Expands every spread a type holds, the owner being the path a refusal names
function Spreads.walk(state: State, node: Type | Pack, owner: string)
	if node.kind == "struct" then
		node.fields = body(state, node.fields, owner)
	elseif node.kind == "enum" then
		for _, variant: Variant in node.variants do
			if variant.fields then
				variant.fields = body(state, variant.fields, `{owner}.{variant.name}`)
			end
		end
	else
		for _, child: Type in Parser.children(node) do
			Spreads.walk(state, child, owner)
		end
	end
end

return Spreads
