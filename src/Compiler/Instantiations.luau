--[[
    Expand's second pass: every reference outside a generic's body whose
    target takes parameters is pointed at the instantiation its arguments
    name, a type declaration of its own, made the first time it is met and
    kept in the order references are met, so labels are deterministic
--]]

--!strict
local Instantiations = {}

local Diagnostics = require("./Diagnostics")
local Parser = require("./Parser")
local Print = require("./Analyse/Print")
local Schema = require("./Config/Types/Schema")
local Spreads = require("./Spreads")

type Diagnostics = Diagnostics.Diagnostics
type Pack = Schema.Pack
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration

export type State = {
	diagnostics: Diagnostics,
	made: { [string]: TypeDeclaration }, -- Every instantiation so far, by its path
	making: { [TypeDeclaration]: TypeDeclaration }, -- Each generic on the way down, and the instantiation it is making
	labels: { [string]: boolean }, -- Every label a named type or an instantiation has taken
	list: { TypeDeclaration },
}

local OWN_PARAMETERS: string = "a generic refers to itself only with its own parameters"

-- A generic's label, then the first _n from 1 that no named type and no earlier instantiation takes
local function labelFor(state: State, generic: TypeDeclaration): string
	local base: string = (generic.path :: string):gsub("%.", "_")
	local index: number = 1

	while state.labels[`{base}_{index}`] do
		index += 1
	end

	local label: string = `{base}_{index}`
	state.labels[label] = true

	return label
end

--[[
    The instantiation a reference's arguments name, made the first time it
    is met and cached by its path before its body is walked, so a generic
    that refers to itself with its own parameters reaches the one being
    made. With other arguments it would need a new one at every level, so
    that is refused and returns nil
--]]

local function instantiate(state: State, generic: TypeDeclaration, reference: any): TypeDeclaration?
	local arguments: { Type } = reference.arguments
	local printed: { string } = {}

	for _, argument: Type in arguments do
		table.insert(printed, Print.type(argument))
	end

	local path: string = `{generic.path}<{table.concat(printed, ", ")}>`
	local made: TypeDeclaration? = state.made[path]

	if made then
		return made
	end

	local outer: TypeDeclaration? = state.making[generic]

	if outer then
		local message: string = `"{generic.path}" refers to itself as {path} inside {outer.path}; {OWN_PARAMETERS}`
		state.diagnostics:error("V3021", message, reference)
		return nil
	end

	local instantiation: TypeDeclaration = {
		kind = "type",
		name = generic.name,
		export = false,
		type = generic.type,
		attributes = generic.attributes,
		spans = generic.spans,
		path = path,
		references = 0,
		generic = generic,
		arguments = arguments,
		label = labelFor(state, generic),
		start = reference.start,
		finish = reference.finish,
	}

	state.made[path] = instantiation
	state.making[generic] = instantiation
	table.insert(state.list, instantiation)

	instantiation.type = Spreads.copy(generic.type, arguments)
	Instantiations.walk(state, instantiation.type)
	state.making[generic] = nil

	return instantiation
end

-- Points every reference a type holds to a generic at its instantiation, its arguments' own references first
function Instantiations.walk(state: State, node: Type | Pack)
	for _, child: Type in Parser.children(node) do
		Instantiations.walk(state, child)
	end

	if node.kind == "reference" and node.target and node.target.parameters then
		node.target = instantiate(state, node.target, node)
	end
end

return Instantiations
