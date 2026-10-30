--[[
    The Luau names a generated module spells out: a method name in the
    schema's casing, the type a value of any schema type is annotated as,
    the export line of every named type, the handle types the API's
    entries fit, and the standalone types module a schema may ask for
--]]

--!strict
local Types = {}

local Contract = require("../Config/Contract")
local Diagnostics = require("../Diagnostics")
local Expressions = require("../Emit/Expressions")
local Reserved = require("../Config/Reserved")
local Roblox = require("../Config/Roblox")
local Schema = require("../Config/Types/Schema")

type Declaration = Schema.Declaration
type Diagnostics = Diagnostics.Diagnostics
type Field = Schema.Field
type File = Schema.File
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration
type Variant = Schema.Variant

--[[
    A handle type: the side whose API has entries of its shape, or
    neither, its lines with each member name in braces, and whether only
    a schema that declares a from: Server function has it
--]]

type Handle = { side: string?, reversed: boolean?, lines: { string } }

local VERSION: string = Contract.version
local BOT: string = "export type Bot = { Name: string }" -- What a bot is to the types module; a realm module takes Volt's

-- The handle types over the packs of the message they fit, which a service field takes an API entry as
local HANDLES: { Handle } = {
	{
		side = "server",
		lines = {
			"export type ServerEvent<A...> = {",
			"\t{fire}: (player: Player | Bot, A...) -> (),",
			"\t{fireAll}: (A...) -> (),",
			"\t{fireList}: (players: { Player | Bot }, A...) -> (),",
			"\t{fireExcept}: (player: Player | Bot, A...) -> (),",
			"\t{fireSet}: (players: { [Player | Bot]: true }, A...) -> (),",
			"}",
		},
	},
	{
		side = "server",
		lines = {
			"export type ServerListener<A...> = {",
			"\t{on}: (listener: (player: Player | Bot, A...) -> ()) -> () -> (),",
			"\t{iter}: () -> () -> (number, Player | Bot, A...),",
			"}",
		},
	},
	{
		side = "server",
		lines = { "export type ServerPolling<A...> = { {iter}: () -> () -> (number, Player | Bot, A...) }" },
	},
	{
		side = "server",
		lines = {
			"export type ServerFunction<A..., R...> = {",
			"\t{on}: (handler: (player: Player | Bot, A...) -> R...) -> () -> (),",
			"}",
		},
	},
	{ side = "client", lines = { "export type ClientEvent<A...> = { {fire}: (A...) -> () }" } },
	{
		side = "client",
		lines = {
			"export type ClientListener<A...> = {",
			"\t{on}: (listener: (A...) -> ()) -> () -> (),",
			"\t{iter}: () -> () -> (number, A...),",
			"}",
		},
	},
	{ side = "client", lines = { "export type ClientPolling<A...> = { {iter}: () -> () -> (number, A...) }" } },
	{ side = "client", lines = { "export type ClientFunction<A..., R...> = { {invoke}: (A...) -> (boolean, R...) }" } },
	{ side = "client", lines = { "export type ClientPromise<A...> = { {invoke}: (A...) -> any }" } },
	{
		side = "server",
		reversed = true,
		lines = {
			"export type ServerInvoke<A..., R...> = {",
			"\t{invoke}: (player: Player | Bot, A...) -> (boolean, R...),",
			"}",
		},
	},
	{
		side = "server",
		reversed = true,
		lines = { "export type ServerPromise<A...> = { {invoke}: (player: Player | Bot, A...) -> any }" },
	},
	{
		side = "client",
		reversed = true,
		lines = {
			"export type ClientHandler<A..., R...> = {",
			"\t{on}: (handler: (A...) -> R...) -> () -> (),",
			"\t{connected}: () -> boolean,",
			"}",
		},
	},
	{
		lines = {
			"export type Exported<T> = {",
			"\t{write}: (value: T) -> (buffer, { any }?),",
			"\t{read}: (packet: buffer, side: { any }?) -> T,",
			"}",
		},
	},
}

-- A method name in the casing the schema asks for; the names are written in camel
function Types.cased(name: string, casing: string): string
	if casing == "pascal" then
		return (name:gsub("^%l", string.upper))
	elseif casing == "snake" then
		return (name:gsub("%u", function (letter: string)
			return `_{letter:lower()}`
		end))
	end
	return name
end

-- The name a named type is exported under, its path with every dot an underscore, or an instantiation's own label
function Types.label(declaration: TypeDeclaration): string
	return declaration.label or ((declaration.path :: string):gsub("%.", "_"))
end

-- A generic's alias over some arguments' annotations
local function applied(generic: TypeDeclaration, arguments: { Type }): string
	local parts: { string } = {}
	for _, argument: Type in arguments do
		table.insert(parts, Types.annotation(argument))
	end
	return `{Types.label(generic)}<{table.concat(parts, ", ")}>`
end

-- The Luau type a value of a named type is annotated as: its label, or for an instantiation its generic's alias
function Types.of(declaration: TypeDeclaration): string
	if declaration.generic then
		return applied(declaration.generic, declaration.arguments :: { Type })
	end
	return Types.label(declaration)
end

-- The fields of a struct or a variant, each typed, as the inside of a table type
local function fields(list: { Field }): string
	local parts: { string } = {}
	for _, field: Field in list do
		table.insert(parts, `{field.name}: {Types.annotation(field.type)}`)
	end
	return table.concat(parts, ", ")
end

-- A table type around some fields, or the empty one
local function record(inside: string): string
	return inside == "" and "{}" or `\{ {inside} }`
end

-- A tagged enum's variant as the table type its values take: the tag holding the variant's name, then its fields
function Types.variant(tag: string, variant: Variant): string
	local own: string = variant.fields and fields(variant.fields) or ""
	local name: string = `{tag}: "{variant.name}"`

	return record(own == "" and name or `{name}, {own}`)
end

--[[
    The Luau type a value of a schema type is annotated as: a named type
    by its label, an instantiation or a generic's body's reference to a
    generic by the alias over its arguments, a type parameter by its name,
    a struct or a tagged variant as a table type, a unit enum as its
    names, a union as its members
--]]

function Types.annotation(node: Type): string
	if node.kind == "reference" then
		if node.parameter then
			return node.name
		end

		local target: TypeDeclaration = node.target :: TypeDeclaration
		return target.parameters and applied(target, node.arguments :: { Type }) or Types.of(target)
	elseif node.kind == "primitive" then
		local name: string = node.name
		local direct: boolean = name == "boolean" or name == "string" or name == "buffer"

		return direct and name or name == "unknown" and "any" or "number"
	elseif node.kind == "roblox" then
		if node.name == "Enum" then
			return `Enum.{node.item}`
		end

		local class: string = node.class or Roblox[node.name].class
		return node.name == "StreamedInstance" and `{class}?` or class
	elseif node.kind == "optional" then
		return `{Types.annotation(node.inner)}?`
	elseif node.kind == "struct" then
		return record(fields(node.fields))
	elseif node.kind == "array" then
		return `\{ {Types.annotation(node.element)} }`
	elseif node.kind == "set" then
		return `\{ [{Types.annotation(node.element)}]: true }`
	elseif node.kind == "map" then
		return `\{ [{Types.annotation(node.key)}]: {Types.annotation(node.value)} }`
	elseif node.kind == "literal" then
		-- A string is its singleton, escaped as a Luau string; Luau has no number singletons, so a number is any number
		local value: string | number | boolean = node.value
		return typeof(value) == "string" and Expressions.quote(value)
			or typeof(value) == "number" and "number"
			or tostring(value)
	end

	local members: { string } = {}

	if node.kind == "enum" then
		for _, variant: Variant in node.variants do
			table.insert(members, node.tag and Types.variant(node.tag, variant) or `"{variant.name}"`)
		end
	else
		for _, member: Type in node.members do
			table.insert(members, Types.annotation(member))
		end
	end

	return table.concat(members, " | ")
end

--[[
    The line of every named type in a declaration list, namespaces walked,
    in declaration order: exported, or local to the module for a private
    one, which the module's own signatures still name. A generic's line is
    its one alias, which every annotation of an instantiation applies
--]]

function Types.named(declarations: { Declaration }, lines: { string }): { string }
	for _, declaration: Declaration in declarations do
		if declaration.kind == "type" then
			local attributes: Schema.Attributes? = declaration.attributes
			local exported: string = (attributes and attributes.private) and "" or "export "
			local names: { string } = {}

			for _, parameter: Schema.Parameter in declaration.parameters or {} do
				table.insert(names, parameter.name)
			end

			local given: string = #names > 0 and `<{table.concat(names, ", ")}>` or ""
			local alias: string = `{exported}type {Types.label(declaration)}{given}`

			table.insert(lines, `{alias} = {Types.annotation(declaration.type)}`)
		elseif declaration.kind == "namespace" then
			Types.named(declaration.declarations, lines)
		end
	end
	return lines
end

-- Every named type's label in a declaration list, namespaces walked
local function labels(declarations: { Declaration }, set: { [string]: boolean }): { [string]: boolean }
	for _, declaration: Declaration in declarations do
		if declaration.kind == "type" then
			set[Types.label(declaration)] = true
		elseif declaration.kind == "namespace" then
			labels(declaration.declarations, set)
		end
	end
	return set
end

--[[
    Refuses a type parameter named like a type the modules declare or
    name, a Roblox type or a named type's label, namespaces walked, since
    it would hide that type inside its generic's alias
--]]

function Types.parameters(declarations: { Declaration }, diagnostics: Diagnostics, taken: { [string]: boolean }?)
	local named: { [string]: boolean } = taken or labels(declarations, {})

	for _, declaration: Declaration in declarations do
		if declaration.kind == "namespace" then
			Types.parameters(declaration.declarations, diagnostics, named)
		elseif declaration.kind == "type" then
			for _, parameter: Schema.Parameter in declaration.parameters or {} do
				local name: string = parameter.name
				local why: string? = (
					table.find(Reserved.types, name) and "a type the generated modules declare or name"
				)
					or (Roblox[name] and "a Roblox type the schema language names")
					or (named[name] and "the label of a named type of the schema")
					or nil

				if why then
					diagnostics:error("V4002", `"{name}" is {why} and cannot name a type parameter`, parameter)
				end
			end
		end
	end
end

-- Whether a declaration list, namespaces walked, declares a function the server calls
function Types.reversed(declarations: { Declaration }): boolean
	for _, declaration: Declaration in declarations do
		if declaration.kind == "function" and declaration.from == "Server" then
			return true
		elseif declaration.kind == "namespace" and Types.reversed(declaration.declarations) then
			return true
		end
	end
	return false
end

--[[
    The handle types of one side, or of both when none is given, each
    with its members in the schema's casing, one text each; exported, or
    local to a module whose schema keeps them in a types module. Those of
    a from: Server function only when the schema declares one
--]]

function Types.handles(side: string?, casing: string, exported: boolean, reversed: boolean): { string }
	local texts: { string } = {}

	for _, handle: Handle in HANDLES do
		local sided: boolean = side == nil or handle.side == nil or handle.side == side

		if sided and (reversed or not handle.reversed) then
			local text: string = table.concat(handle.lines, "\n")
			local cased: string = text:gsub("{(%a+)}", function (name: string)
				return Types.cased(name, casing)
			end)

			table.insert(texts, exported and cased or (cased:gsub("^export ", "")))
		end
	end

	return texts
end

--[[
    The standalone types module: every named type, then the bot and every
    handle type, for code shared between the client and the server
--]]

function Types.module(file: File, name: string): string
	local casing: string = file.options.casing :: string
	local named: { string } = Types.named(file.declarations, {})
	local parts: { string } = {
		"--[[",
		`    The types module Volt {VERSION} generated from {name}: every named type of`,
		"    the schema and the handle types the generated API's entries fit, for",
		"    code shared between the client and the server. Generated code: change",
		"    the schema and run volt again rather than editing this file",
		"--]]",
		"",
		"--!strict",
	}

	if #named > 0 then
		table.insert(parts, `{table.concat(named, "\n")}\n`)
	end

	table.insert(parts, `{BOT}\n`)

	for _, handle: string in Types.handles(nil, casing, true, Types.reversed(file.declarations)) do
		table.insert(parts, `{handle}\n`)
	end

	table.insert(parts, "return {}\n")
	return table.concat(parts, "\n")
end

return Types
