--[[
    The Luau names a generated module spells out: a method name in the
    schema's casing, the type a value of any schema type is annotated as,
    the export line of every named type, the handle types the API's
    entries fit, and the standalone types module a schema may ask for
--]]

--!strict
local Types = {}

local Contract = require("../Config/Contract")
local Roblox = require("../Config/Roblox")
local Schema = require("../Config/Types/Schema")

type Declaration = Schema.Declaration
type Field = Schema.Field
type File = Schema.File
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration
type Variant = Schema.Variant

-- A handle type: the side whose API has entries of its shape, or neither, and its lines with each member name in braces
type Handle = { name: string, side: string?, lines: { string } }

local VERSION: string = Contract.version

-- The handle types over the packs of the message they fit, which a service field takes an API entry as
local HANDLES: { Handle } = {
	{
		name = "ServerEvent",
		side = "server",
		lines = {
			"export type ServerEvent<A...> = {",
			"\t{fire}: (player: Player, A...) -> (),",
			"\t{fireAll}: (A...) -> (),",
			"\t{fireList}: (players: { Player }, A...) -> (),",
			"\t{fireExcept}: (player: Player, A...) -> (),",
			"\t{fireSet}: (players: { [Player]: true }, A...) -> (),",
			"}",
		},
	},
	{
		name = "ServerListener",
		side = "server",
		lines = {
			"export type ServerListener<A...> = {",
			"\t{on}: (listener: (player: Player, A...) -> ()) -> () -> (),",
			"\t{iter}: () -> () -> (number, Player, A...),",
			"}",
		},
	},
	{
		name = "ServerFunction",
		side = "server",
		lines = {
			"export type ServerFunction<A..., R...> = { {on}: (handler: (player: Player, A...) -> R...) -> () -> () }",
		},
	},
	{ name = "ClientEvent", side = "client", lines = { "export type ClientEvent<A...> = { {fire}: (A...) -> () }" } },
	{
		name = "ClientListener",
		side = "client",
		lines = {
			"export type ClientListener<A...> = {",
			"\t{on}: (listener: (A...) -> ()) -> () -> (),",
			"\t{iter}: () -> () -> (number, A...),",
			"}",
		},
	},
	{
		name = "ClientFunction",
		side = "client",
		lines = { "export type ClientFunction<A..., R...> = { {invoke}: (A...) -> (boolean, R...) }" },
	},
	{
		name = "ClientPromise",
		side = "client",
		lines = { "export type ClientPromise<A...> = { {invoke}: (A...) -> any }" },
	},
	{
		name = "Exported",
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

-- The name a named type is exported under: its path with every dot an underscore
function Types.label(declaration: TypeDeclaration): string
	return ((declaration.path :: string):gsub("%.", "_"))
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

--[[
    The Luau type a value of a schema type is annotated as: a named type
    by its label, a struct or a tagged variant as a table type, a unit
    enum as its names, a union as its members
--]]

function Types.annotation(node: Type): string
	if node.kind == "reference" then
		return Types.label(node.target :: TypeDeclaration)
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
	end

	local members: { string } = {}

	if node.kind == "enum" then
		for _, variant: Variant in node.variants do
			local name: string = `"{variant.name}"`

			if node.tag then
				local own: string = variant.fields and fields(variant.fields) or ""
				name = record(own == "" and `{node.tag}: {name}` or `{node.tag}: {name}, {own}`)
			end

			table.insert(members, name)
		end
	else
		for _, member: Type in node.members do
			table.insert(members, Types.annotation(member))
		end
	end

	return table.concat(members, " | ")
end

-- The export line of every named type in a declaration list, namespaces walked, in declaration order
function Types.named(declarations: { Declaration }, lines: { string }): { string }
	for _, declaration: Declaration in declarations do
		if declaration.kind == "type" then
			table.insert(lines, `export type {Types.label(declaration)} = {Types.annotation(declaration.type)}`)
		elseif declaration.kind == "namespace" then
			Types.named(declaration.declarations, lines)
		end
	end
	return lines
end

--[[
    The handle types of one side, or of both when none is given, each
    with its members in the schema's casing, one text each
--]]

function Types.handles(side: string?, casing: string): { string }
	local texts: { string } = {}

	for _, handle: Handle in HANDLES do
		if side == nil or handle.side == nil or handle.side == side then
			local text: string = table.concat(handle.lines, "\n")

			table.insert(texts, (text:gsub("{(%a+)}", function (name: string)
				return Types.cased(name, casing)
			end)))
		end
	end

	return texts
end

--[[
    The standalone types module: every named type, then every handle
    type, for code shared between the client and the server
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

	for _, handle: string in Types.handles(nil, casing) do
		table.insert(parts, `{handle}\n`)
	end

	table.insert(parts, "return {}\n")
	return table.concat(parts, "\n")
end

return Types
