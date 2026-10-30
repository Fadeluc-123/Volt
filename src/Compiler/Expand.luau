--[[
    Turns what a schema writes once and uses in several places into plain
    named types, the last step of resolution: spreads become the fields
    they name, references to generics point at instantiations, references
    are counted, and the recursive types are found and held to having a
    value that ends, so nothing after it knows a spread or a template
--]]

--!strict
local Expand = {}

local Diagnostics = require("./Diagnostics")
local Instantiations = require("./Instantiations")
local Parser = require("./Parser")
local Recursion = require("./Recursion")
local Schema = require("./Config/Types/Schema")
local Spreads = require("./Spreads")

type Declaration = Schema.Declaration
type Diagnostics = Diagnostics.Diagnostics
type File = Schema.File
type Pack = Schema.Pack
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration

--[[
    Calls back with every type a schema's declarations hold that is no
    generic's body, namespaces walked, in declaration order, each with the
    path of what holds it: a named type's, a message's data and its return
--]]

local function eachRoot(declarations: { Declaration }, visit: (Type | Pack, string) -> ())
	for _, declaration: Declaration in declarations do
		local path: string = declaration.path :: string

		if declaration.kind == "namespace" then
			eachRoot(declaration.declarations, visit)
		elseif declaration.kind == "type" then
			if not declaration.parameters then
				visit(declaration.type, path)
			end
		elseif declaration.kind == "event" then
			if declaration.data then
				visit(declaration.data, path)
			end
		elseif declaration.kind == "function" then
			if declaration.data then
				visit(declaration.data, path)
			end

			if declaration["return"] then
				visit(declaration["return"], path)
			end
		end
	end
end

-- Every named type a schema declares, generics among them, namespaces walked, in declaration order
local function allNamed(declarations: { Declaration }, list: { TypeDeclaration }): { TypeDeclaration }
	for _, declaration: Declaration in declarations do
		if declaration.kind == "namespace" then
			allNamed(declaration.declarations, list)
		elseif declaration.kind == "type" then
			table.insert(list, declaration)
		end
	end

	return list
end

--[[
    Adds one to the target of every reference a type holds. A reference's
    arguments are not counted, since what the type holds of them is its
    instantiation's body, which is counted once
--]]

local function count(node: Type | Pack)
	if node.kind == "reference" then
		if node.target then
			node.target.references = (node.target.references :: number) + 1
		end
		return
	end

	for _, child: Type in Parser.children(node) do
		count(child)
	end
end

--[[
    Expands a resolved file in place, in four passes over the declarations,
    the messages' data and returns, and what the earlier passes made. After
    it no spread entry is left anywhere, outside a generic's body no
    reference targets a generic, and references leaves generic bodies out
--]]

function Expand.file(file: File, diagnostics: Diagnostics)
	local spreading: Spreads.State = { diagnostics = diagnostics, spreading = {} }
	local instantiating: Instantiations.State =
		{ diagnostics = diagnostics, made = {}, making = {}, labels = {}, list = {} }
	local declared: { TypeDeclaration } = allNamed(file.declarations, {})

	-- 1) Spreads, every named type's before the bodies a message writes in place, a generic's body among them
	for _, declaration: TypeDeclaration in declared do
		local label: string = (declaration.path :: string):gsub("%.", "_")

		instantiating.labels[label] = true
		Spreads.declaration(spreading, declaration)
	end

	eachRoot(file.declarations, function (node: Type | Pack, path: string)
		Spreads.walk(spreading, node, path)
	end)

	-- 2) Instantiations, in the order references are met
	eachRoot(file.declarations, function (node: Type | Pack)
		Instantiations.walk(instantiating, node)
	end)

	-- 3) References, a generic's body counting once per instantiation
	eachRoot(file.declarations, count)

	for _, instantiation: TypeDeclaration in instantiating.list do
		count(instantiation.type)
	end

	-- 4) Recursion, over every named type that is no template
	local named: { TypeDeclaration } = {}

	for _, declaration: TypeDeclaration in declared do
		if not declaration.parameters then
			table.insert(named, declaration)
		end
	end

	table.move(instantiating.list, 1, #instantiating.list, #named + 1, named)
	Recursion.check(diagnostics, named)

	file.instantiations = instantiating.list
end

return Expand
