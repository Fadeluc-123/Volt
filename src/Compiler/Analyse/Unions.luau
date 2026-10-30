--[[
    What a type is at runtime, which is what the writer tells a union's
    members apart by: the type a name stands for, whether a member is a
    unit enum, the variants unit enums flatten into and the runtime classes
    a member can be, through references and nested unions
--]]

--!strict
local Unions = {}

local Roblox = require("../Config/Roblox")
local Schema = require("../Config/Types/Schema")

type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration
type Variant = Schema.Variant

--[[
    Follows references to the type they name, so a rule about what a value
    is at runtime sees through named types. A cycle of plain names stops at
    the reference that would pass a name again
--]]

function Unions.resolved(node: Type): Type
	local passed: { [TypeDeclaration]: boolean } = {}

	while node.kind == "reference" and node.target and not passed[node.target] do
		passed[node.target] = true
		node = node.target.type
	end

	return node
end

-- Two unit enums in one union flatten their variants into one discriminant, so they never clash
function Unions.isUnitEnum(node: Type): boolean
	local actual: Type = Unions.resolved(node)
	return actual.kind == "enum" and actual.tag == nil
end

--[[
    The variants of a union whose members are all unit enums, which
    flatten into one discriminant, or nil when any member is not one
--]]

function Unions.flattened(members: { Type }): { Variant }?
	local variants: { Variant } = {}
	for _, member: Type in members do
		local actual: Type = Unions.resolved(member)
		if actual.kind ~= "enum" or actual.tag then
			return nil
		end
		table.move(actual.variants, 1, #actual.variants, #variants + 1, variants)
	end
	return variants
end

-- A union met again inside itself has no classes of its own, so one that holds itself ends here
local function classes(node: Type, walking: { [Type]: boolean }): { string }
	local actual: Type = Unions.resolved(node)

	if actual.kind == "union" then
		local list: { string } = {}

		if walking[actual] then
			return list
		end

		walking[actual] = true

		for _, member: Type in actual.members do
			for _, class: string in classes(member, walking) do
				table.insert(list, class)
			end
		end

		walking[actual] = nil
		return list
	elseif actual.kind == "primitive" then
		local name: string = actual.name
		local named: boolean = name == "boolean" or name == "string" or name == "buffer" or name == "unknown"

		return { named and name or "number" }
	elseif actual.kind == "roblox" then
		return { Roblox[actual.name].class }
	elseif actual.kind == "enum" then
		return { actual.tag and "table" or "string" }
	elseif actual.kind == "optional" then
		return { "nil" }
	elseif actual.kind == "literal" then
		return { typeof(actual.value) }
	elseif actual.kind == "reference" then
		return {} -- Unresolved and already reported, or a cycle of plain names
	end

	return { "table" }
end

-- The runtime classes a union member can be, through references and nested unions
function Unions.classes(node: Type): { string }
	return classes(node, {})
end

return Unions
