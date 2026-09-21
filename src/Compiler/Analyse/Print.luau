--[[
    Prints a resolved file in its canonical form, which --ast shows and
    the schema hash is taken over: the options in their fixed order, then
    every declaration on one line with references spelled as full paths,
    record keys in shape order, a namespace's declarations indented under
    it, and each declaration annotated with what analysis found
--]]

--!strict
local Print = {}

local Options = require("../Config/Options")
local Schema = require("../Config/Types/Schema")
local Sizes = require("./Sizes")

type Declaration = Schema.Declaration
type Field = Schema.Field
type File = Schema.File
type Pack = Schema.Pack
type Range = Schema.Range
type Size = Sizes.Size
type Spec = Options.Spec
type Type = Schema.Type

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
		return `{node.name}{printRange(node.range, "(", ")")}`
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

	return node.target and node.target.path or node.name
end

function printFields(list: { Field }): string
	local parts: { string } = {}
	for _, field: Field in list do
		table.insert(parts, `{field.name}: {Print.type(field.type)}`)
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

local function blockBytes(node: (Type | Pack)?): string
	local low: number, high: number = Sizes.block(node and Sizes.size(node) or Sizes.fixed(0))
	return bytes(low, high)
end

--[[
    What resolution and analysis found out about a declaration, as a
    trailing comment; nothing before resolution, so a parsed tree prints
    back as written
--]]

local function annotate(node: Declaration): string
	local parts: { string } = {}

	if node.kind == "type" and node.references then
		local size: Size = Sizes.size(node.type)
		local plural: string = node.references == 1 and "" or "s"

		table.insert(parts, bytes(size.min, size.max))
		if size.bits > 0 then
			table.insert(parts, `{size.bits} flag bit{size.bits == 1 and "" or "s"}`)
		end

		table.insert(parts, `{node.references} reference{plural}`)
	elseif node.kind == "event" and (node.toServer or node.toClient) then
		if node.toServer then
			table.insert(parts, `to server {node.toServer}`)
		end

		if node.toClient then
			table.insert(parts, `to client {node.toClient}`)
		end

		table.insert(parts, `payload {blockBytes(node.data)}`)
	elseif node.kind == "function" and node.toServer then
		table.insert(parts, `to server {node.toServer}`)
		table.insert(parts, `to client {node.toClient}`)
		table.insert(parts, `data {blockBytes(node.data)}`)
		table.insert(parts, `return {blockBytes(node["return"])}`)
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
		return `{indent}{node.export and "export " or ""}type {node.name} = {Print.type(node.type)}{annotate(node)}`
	elseif node.kind == "namespace" then
		local inner: { string } = {}
		for _, declaration: Declaration in node.declarations do
			table.insert(inner, printDeclaration(declaration, `{indent}\t`))
		end

		return #inner == 0 and `{indent}namespace {node.name} \{}`
			or `{indent}namespace {node.name} \{\n{table.concat(inner, "\n")}\n{indent}}`
	end

	local entries: { string } = {}
	for _, spec: Spec in node.kind == "event" and Options.event or Options["function"] do
		local value: any = (node :: any)[spec.key]
		if value ~= nil then
			table.insert(entries, `{spec.key}: {printValue(value)}`)
		end
	end

	local record: string = #entries == 0 and "{}" or `\{ {table.concat(entries, ", ")} }`
	return `{indent}{node.kind} {node.name} {record}{annotate(node)}`
end

--[[
    Prints a file in its canonical form: the options in their fixed order,
    then the declarations, one per line and each annotated with what
    resolution and analysis found. This text is what the schema hash covers
--]]

function Print.file(file: File): string
	local lines: { string } = {}

	for _, spec: Spec in Options.file do
		local value: any = (file.options :: any)[spec.key]
		if value ~= nil then
			table.insert(lines, `option {spec.key} = {spec.kind == "string" and `"{value}"` or tostring(value)}`)
		end
	end

	for _, declaration: Declaration in file.declarations do
		table.insert(lines, printDeclaration(declaration, ""))
	end

	return table.concat(lines, "\n")
end

return Print
