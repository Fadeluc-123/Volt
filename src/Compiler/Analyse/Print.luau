--[[
    Prints a resolved file in its canonical form, which --ast shows and
    the schema hash is taken over: the options in their fixed order, then
    every declaration on one line, its attributes first, with references
    spelled as full paths, record keys in shape order, a namespace's
    declarations indented under it, and each annotated with what analysis
    found
--]]

--!strict
local Print = {}

local Attributes = require("../Config/Attributes")
local Options = require("../Config/Options")
local Schema = require("../Config/Types/Schema")
local Sizes = require("./Sizes")

type Attribute = Attributes.Attribute
type Declaration = Schema.Declaration
type Field = Schema.Field
type File = Schema.File
type Pack = Schema.Pack
type Parameter = Schema.Parameter
type Range = Schema.Range
type Size = Sizes.Size
type Spec = Options.Spec
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration

local printFields: ({ Field }) -> string

-- A bound printed as a whole number, however large
function Print.whole(value: number): string
	return string.format("%.0f", value)
end

local function printRange(range: Range?, open: string, close: string): string
	if not range then
		return ""
	end

	local min: string = range.min and tostring(range.min) or ""
	local max: string = range.max and tostring(range.max) or ""

	return range.min == range.max and `{open}{min}{close}` or `{open}{min}..{max}{close}`
end

--[[
    Prints a type as schema source, with a reference spelled as the full
    path of what it resolved to
--]]

function Print.type(node: Type): string
	if node.kind == "primitive" then
		return `{node.name}{node.utf8 and ".utf8" or ""}{printRange(node.range, "(", ")")}`
	elseif node.kind == "literal" then
		return typeof(node.value) == "string" and `"{node.value}"` or tostring(node.value)
	elseif node.kind == "roblox" then
		local generics: { string } = {}
		for _, generic: Type in (node.generics or {}) :: { Type } do
			table.insert(generics, Print.type(generic))
		end

		local item: string = node.item and `.{node.item}` or ""
		local class: string = node.class and `({node.class})` or ""
		local arguments: string = #generics > 0 and `<{table.concat(generics, ", ")}>` or ""

		return `{node.name}{item}{class}{arguments}`
	elseif node.kind == "struct" then
		return `struct \{ {printFields(node.fields)} }`
	elseif node.kind == "enum" then
		local variants: { string } = {}
		for _, variant in node.variants do
			table.insert(
				variants,
				variant.fields and `{variant.name} \{ {printFields(variant.fields)} }` or variant.name
			)
		end

		local tag: string = node.tag and `"{node.tag}" ` or ""
		return `enum {tag}\{ {table.concat(variants, ", ")} }`
	elseif node.kind == "set" then
		return `set<{Print.type(node.element)}>{printRange(node.range, "(", ")")}`
	elseif node.kind == "map" then
		return `\{ [{Print.type(node.key)}]: {Print.type(node.value)} }{printRange(node.range, "(", ")")}`
	elseif node.kind == "array" then
		return `{Print.type(node.element)}{node.range and printRange(node.range, "[", "]") or "[]"}`
	elseif node.kind == "optional" then
		return `{Print.type(node.inner)}?`
	elseif node.kind == "union" then
		local members: { string } = {}
		for _, member: Type in node.members do
			table.insert(members, Print.type(member))
		end

		return table.concat(members, " | ")
	end

	local target: TypeDeclaration? = node.target
	local path: string = target and target.path or node.name

	-- An instantiation's path already spells its arguments
	if not node.arguments or (target and target.generic) then
		return path
	end

	local arguments: { string } = {}
	for _, argument: Type in node.arguments do
		table.insert(arguments, Print.type(argument))
	end

	return `{path}<{table.concat(arguments, ", ")}>`
end

function printFields(list: { Field }): string
	local parts: { string } = {}
	for _, field: Field in list do
		table.insert(parts, field.spread and `..{Print.type(field.type)}` or `{field.name}: {Print.type(field.type)}`)
	end

	return table.concat(parts, ", ")
end

--[[
    Prints a record value: a parameter pack, a type, or a plain value
--]]

local function printValue(value: any): string
	if typeof(value) ~= "table" then
		return tostring(value)
	end

	return value.kind == "pack" and `({printFields(value.parameters)})` or Print.type(value)
end

local function bytes(low: number, high: number): string
	return low == high and `{Print.whole(low)} bytes` or `{Print.whole(low)}..{Print.whole(high)} bytes`
end

-- A payload's bytes as a block, a @delta event's sized as its mask and the fields it can send
local function blockBytes(node: (Type | Pack)?, delta: boolean): string
	local size: Size = node and (delta and Sizes.delta(node) or Sizes.size(node)) or Sizes.fixed(0)
	local low: number, high: number = Sizes.block(size)
	return bytes(low, high)
end

-- A declaration's attributes in the rows' order, so their order in the source never changes the hash
local function printAttributes(set: Schema.Attributes?): string
	local attributes: { string } = {}
	for _, row: Attribute in Attributes do
		local value: (boolean | number)? = set and set[row.name]

		if value then
			table.insert(attributes, typeof(value) == "number" and `@{row.name}({value}) ` or `@{row.name} `)
		end
	end

	return table.concat(attributes)
end

-- A generic's parameters as written after its name, or nothing for any other type
local function printParameters(list: { Parameter }?): string
	local names: { string } = {}
	for _, parameter: Parameter in list or {} do
		table.insert(names, parameter.name)
	end

	return #names > 0 and `<{table.concat(names, ", ")}>` or ""
end

--[[
    What resolution and analysis found out about a declaration, as a
    trailing comment; nothing before resolution, so a parsed tree prints
    back as written, and nothing for a generic, which is only a template.
    A recursive type is sized as a value at level 1, its contents at level 2
--]]

local function annotate(node: Declaration): string
	local parts: { string } = {}

	if node.kind == "type" and node.references and not node.parameters then
		local size: Size = Sizes.size(node.type, node.depth and 2 or nil)
		local plural: string = node.references == 1 and "" or "s"

		table.insert(parts, bytes(size.min, size.max))
		if size.bits > 0 then
			table.insert(parts, `{size.bits} flag bit{size.bits == 1 and "" or "s"}`)
		end

		table.insert(parts, `{node.references} reference{plural}`)

		if node.depth then
			table.insert(parts, `depth {node.depth}`)
		end
	elseif node.kind == "event" then
		if node.toServer then
			table.insert(parts, `to server {node.toServer}`)
		end

		if node.toClient then
			table.insert(parts, `to client {node.toClient}`)
		end

		-- An event with no ids has not been analysed, and prints back as written
		if #parts > 0 then
			local delta: boolean = node.attributes ~= nil and node.attributes.delta == true
			table.insert(parts, `payload {blockBytes(node.data, delta)}`)
		end
	elseif node.kind == "function" and node.toServer then
		table.insert(parts, `to server {node.toServer}`)
		table.insert(parts, `to client {node.toClient}`)
		table.insert(parts, `data {blockBytes(node.data, false)}`)
		table.insert(parts, `return {blockBytes(node["return"], false)}`)
	end

	return #parts == 0 and "" or ` -- {table.concat(parts, ", ")}`
end

--[[
    Prints a declaration as schema source, one line each, with record keys
    in shape order, struct and enum declarations in their type form, and a
    namespace's declarations indented under it
--]]

local function printDeclaration(node: Declaration, indent: string): string
	if node.kind == "type" then
		local exported: string = node.export and "export " or ""
		local named: string =
			`{printAttributes(node.attributes)}{exported}type {node.name}{printParameters(node.parameters)}`

		return `{indent}{named} = {Print.type(node.type)}{annotate(node)}`
	elseif node.kind == "namespace" then
		local inner: { string } = {}
		for _, declaration: Declaration in node.declarations do
			table.insert(inner, printDeclaration(declaration, `{indent}\t`))
		end

		return #inner == 0 and `{indent}namespace {node.name} \{}`
			or `{indent}namespace {node.name} \{\n{table.concat(inner, "\n")}\n{indent}}`
	elseif node.kind == "channel" then
		return `{indent}channel {node.name}`
	end

	local entries: { string } = {}
	for _, spec: Spec in node.kind == "event" and Options.event or Options["function"] do
		local value: any = (node :: any)[spec.key]
		if value ~= nil then
			table.insert(entries, `{spec.key}: {printValue(value)}`)
		end
	end

	local record: string = #entries == 0 and "{}" or `\{ {table.concat(entries, ", ")} }`
	local attributes: string = printAttributes(node.kind == "event" and node.attributes or nil)

	return `{indent}{attributes}{node.kind} {node.name} {record}{annotate(node)}`
end

--[[
    Prints a file in its canonical form: the options in their fixed order,
    but for the build options, which change nothing on the wire, then the
    declarations, one per line and each annotated with what resolution and
    analysis found. This text is what the schema hash covers
--]]

function Print.file(file: File): string
	local lines: { string } = {}

	for _, spec: Spec in Options.file do
		local value: any = (file.options :: any)[spec.key]
		if value ~= nil and not spec.build then
			table.insert(lines, `option {spec.key} = {spec.kind == "string" and `"{value}"` or tostring(value)}`)
		end
	end

	for _, declaration: Declaration in file.declarations do
		table.insert(lines, printDeclaration(declaration, ""))
	end

	return table.concat(lines, "\n")
end

return Print
