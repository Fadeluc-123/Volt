--[[
    The composite walks that are not collections, merged onto the
    emitter: a struct read into locals and built as one table, an
    optional as a flag bit and a child block, the discriminant a choice
    is carried by, an enum with a branch per variant that has fields,
    and a union with a branch per member found by typeof
--]]

--!strict
local Composites = {}

local Blocks = require("../Blocks")
local EmitTypes = require("../Config/Types/Emit")
local Expressions = require("./Expressions")
local Print = require("../Analyse/Print")
local Schema = require("../Config/Types/Schema")
local Sizes = require("../Analyse/Sizes")
local Types = require("../Targets/Types")
local Unions = require("../Analyse/Unions")

type Block = Blocks.Block
type Emit = EmitTypes.Emit
type Field = Schema.Field
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration
type Variant = Schema.Variant

local group = Expressions.group
local refuse = Expressions.refuse

--[[
    Whether a type reads back as its value in place, which only a literal
    does, rather than through a local typed as it is; a shared named type
    reads back through its pair whatever it holds
--]]

local function inPlace(node: Type): boolean
	if node.kind == "reference" then
		local target: TypeDeclaration = node.target :: TypeDeclaration
		return not Sizes.shared(target) and inPlace(target.type)
	end
	return node.kind == "literal"
end

--[[
    A struct: its fields in order, each read into a local, then one
    table constructor after every field's bytes, typed as the struct
    when a field reads back as a literal, which an untyped table widens
--]]

function Composites.struct(
	self: Emit,
	node: Type,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local result: string = read:name(hint)
	local parts: { string } = {}
	local typed: boolean = false

	self:shape(write, value, "table", path)
	self._known = false

	for _, field: Field in (node :: any).fields :: { Field } do
		local place: string = `{value}.{field.name}`

		typed = typed or inPlace(field.type)
		table.insert(
			parts,
			`{field.name} = {self:type(field.type, write, read, place, field.name, `{path}.{field.name}`)}`
		)
	end

	local body: string = #parts == 0 and "" or ` {table.concat(parts, ", ")} `
	local annotation: string = typed and `: {Types.annotation(node)}` or ""

	read:tail(`local {result}{annotation} = \{{body}}`)

	return result
end

--[[
    An optional: one flag bit for presence, and the payload as a child
    block under it, read into a local declared before the branch
--]]

function Composites.optional(
	self: Emit,
	node: Type,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local inner: Type = (node :: any).inner

	-- unknown carries its own presence bit, so nil is already a value it holds
	if Sizes.isPrimitive(inner, "unknown") then
		return self:unknown(write, read, value, hint, path)
	end

	local word: string, bit: number = write:flag()
	local mask: number = 2 ^ bit
	local result: string = read:name(hint)
	local writes: boolean = self._validate or not inPlace(inner) -- A literal nothing checks writes nothing at all

	read:flag()
	write:line(`{word} += {value} ~= nil and {mask} or 0`)
	read:line(`local {result}: {Types.annotation(node)}`)

	if writes then
		write:open(`if {value} ~= nil then`)
	end

	read:open(`if bit32.btest({word}, {mask}) then`)

	self:nested(inner, write:child(path), read:child(path), value, hint, path, result)

	if writes then
		write:close("end")
	end

	read:close("end")

	return result
end

--[[
    Walks a type as a block of its own on both sides, with the flag bytes
    its bits need, and hands the read side's value to an outer local, cast
    to the type that local takes it as when one is given
--]]

function Composites.nested(
	self: Emit,
	node: Type,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string,
	target: string,
	cast: string?
)
	local bits: number = Sizes.size(node).bits

	write:flags(bits)
	read:flags(bits)

	local result: string = self:type(node, write, read, value, hint, path)
	read:tail(cast and `{target} = {result} :: {cast}` or `{target} = {result}`)

	write:done()
	read:done()
end

--[[
    The discriminant of a choice: flag bits while a byte holds the count,
    a raw u16 among the fixed bytes above that, nothing for one variant.
    Returns what writes a zero-based index and the expression reading it
--]]

function Composites.tag(_: Emit, count: number, write: Block, read: Block): ((string) -> (), string)
	local bits: number, bytes: number = Sizes.discriminant(count)
	if bytes > 0 then
		local index: number = write:reserve(bytes)
		local at: number = read:reserve(bytes)

		return function (expression: string)
			write:line(`buffer.writeu16({write.out}, {write:at(index)}, {expression})`)
		end,
			`buffer.readu16(packet, {read:at(at)})`
	elseif bits == 0 then
		return function () end, "0"
	end

	local word: string, bit: number = write:flag(bits)
	local scale: string = bit == 0 and "" or ` * {2 ^ bit}`

	read:flag(bits)

	return function (expression: string)
		write:line(`{word} += {scale == "" and expression or group(expression)}{scale}`)
	end,
		`bit32.extract({word}, {bit}, {bits})`
end

--[[
    An enum: a table of its variant names the writer finds the tag in and
    the reader takes the name from, refused on every build when the name
    is not there since nothing else could be written. A tagged enum then
    carries the variant's fields in a block of its own per branch
--]]

function Composites.enum(
	self: Emit,
	node: Type,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local tag: string? = (node :: any).tag
	local variants: { Variant } = (node :: any).variants
	local printed: string = Print.type(node)
	local quoted: { string } = {}

	for _, variant: Variant in variants do
		table.insert(quoted, `"{variant.name}"`)
	end

	if tag then
		self:shape(write, value, "table", path)
	end

	-- The names keep their literal types, so a value read from them is the enum a checker was told it is
	local literal: string = table.concat(quoted, " | ")
	local names: string = self:constant(printed, path, function (constant: string): string
		return `local {constant}: \{ {literal} } = \{ {table.concat(quoted, ", ")} }`
	end)

	local index: string = write:name(`{hint}Index`)
	local result: string = read:name(hint)
	local store: (string) -> (), fetch: string = self:tag(#variants, write, read)

	-- A name the enum lacks finds no index, which is 0 here so the local is a number the checker can follow
	write:line(`local {index}: number = table.find({names}, {tag and `{value}.{tag}` or value}) or 0`)

	refuse(write, `{index} == 0`, `{path}: expected {printed}`)
	store(`{index} - 1`)

	if not tag then
		read:line(`local {result}: ({literal})? = {names}[{fetch == "0" and "1" or `{fetch} + 1`}]`)
		refuse(read, `not {result}`, `{path}: out of range`)
		return result
	end

	local which: string = read:name(`{hint}Tag`)
	local written: number = 0 -- Variants with nothing to write take no branch on the write side

	read:line(`local {which}: number = {fetch}`)
	read:line(`local {result}: {Types.annotation(node)}`)

	self._known = false

	for position: number, variant: Variant in variants do
		local fields: { Field } = variant.fields or {}
		local body: Type = { kind = "struct", fields = fields, start = 0, finish = 0 }
		local writeVariant: Block = write:child(path)
		local readVariant: Block = read:child(path)
		local parts: { string } = { `{tag} = "{variant.name}"` }
		local bits: number = Sizes.size(body).bits

		writeVariant:flags(bits)
		readVariant:flags(bits)

		-- Inside its branch the value is the variant, which is what lets a checker read the variant's fields
		local cast: string = writeVariant:name(`{hint}{variant.name}`)

		if #fields > 0 then
			writeVariant:line(`local {cast} = {value} :: {Types.variant(tag, variant)}`)
		end

		for _, field: Field in fields do
			local place: string = `{cast}.{field.name}`
			local fieldPath: string = `{path}.{field.name}`

			table.insert(
				parts,
				`{field.name} = {self:type(field.type, writeVariant, readVariant, place, field.name, fieldPath)}`
			)
		end

		if not writeVariant:empty() then
			written += 1

			if written == 1 then
				write:open(`if {index} == {position} then`)
			else
				write:tail(`elseif {index} == {position} then`)
			end

			writeVariant:done()
		end

		if position == 1 then
			read:open(`if {which} == 0 then`)
		else
			read:tail(`elseif {which} == {position - 1} then`)
		end

		readVariant:tail(`{result} = \{ {table.concat(parts, ", ")} }`)
		readVariant:done()
	end

	if written > 0 then
		write:close("end")
	end

	read:close(`else\n\terror("{path}: out of range")\nend`)

	return result
end

--[[
    A union: the member a value belongs to, found by typeof, as a tag,
    then the member in a block of its own per branch. Members that are
    all unit enums flatten into one enum of every variant
--]]

function Composites.union(
	self: Emit,
	node: Type,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local members: { Type } = (node :: any).members
	local variants: { Variant }? = Unions.flattened(members)

	if variants then
		local flat: Type = { kind = "enum", variants = variants, start = node.start, finish = node.finish }
		return self:enum(flat, write, read, value, hint, path)
	end

	local index: string = write:name(`{hint}Member`)
	local result: string = read:name(hint)
	local which: string = read:name(`{hint}Tag`)
	local store: (string) -> (), fetch: string = self:tag(#members, write, read)
	local known: boolean = self._known
	local terms: { string } = {}

	for position: number, member: Type in members do
		local classes: { string } = {}
		for _, class: string in Unions.classes(member) do
			table.insert(classes, `typeof({value}) == "{class}"`)
		end

		local test: string = #classes == 1 and classes[1] or `({table.concat(classes, " or ")})`
		table.insert(terms, `{test} and {position - 1}`)
	end

	-- A value matching no member takes -1, so the local is a number the checker can follow
	write:line(`local {index}: number = {table.concat(terms, " or ")} or -1`)

	refuse(write, `{index} < 0`, `{path}: expected {Print.type(node)}`)
	store(index)

	read:line(`local {which}: number = {fetch}`)
	read:line(`local {result}: {Types.annotation(node)}`)

	local written: number = 0 -- Members with nothing to write, a literal nothing checks, take no branch on the write side

	for position: number, member: Type in members do
		if self._validate or not inPlace(member) then
			written += 1

			if written == 1 then
				write:open(`if {index} == {position - 1} then`)
			else
				write:tail(`elseif {index} == {position - 1} then`)
			end
		end

		if position == 1 then
			read:open(`if {which} == 0 then`)
		else
			read:tail(`elseif {which} == {position - 1} then`)
		end

		-- Inside its branch the value is the member typeof found, which is what lets a checker follow it both ways
		local annotation: string = Types.annotation(member)
		local cast: string = `({value} :: {annotation})`

		self._known = true
		self:nested(member, write:child(path), read:child(path), cast, hint, path, result, annotation)
	end

	self._known = known

	if written > 0 then
		write:close("end")
	end

	read:close(`else\n\terror("{path}: out of range")\nend`)

	return result
end

return Composites
