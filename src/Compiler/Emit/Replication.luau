--[[
    The replication walks, merged onto the emitter: a @delta event's
    struct, each field a block of its own sent under its bit of the mask
    the writer is handed, and a @dictionary string, carried as the id the
    runtime's dictionary gives it
--]]

--!strict
local Replication = {}

local Blocks = require("../Blocks")
local EmitTypes = require("../Config/Types/Emit")
local Expressions = require("./Expressions")
local Schema = require("../Config/Types/Schema")
local Sizes = require("../Analyse/Sizes")
local Types = require("../Targets/Types")
local Wire = require("../Config/Wire")

type Block = Blocks.Block
type Emit = EmitTypes.Emit
type Field = Schema.Field
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration

local DICTIONARY_BYTES: number = Wire.dictionaryBytes

local refuse = Expressions.refuse

--[[
    The condition a string's length breaks its type's bounds by and the
    refusal that says so, worded as the length rule words them for a
    string that carries its own bytes
--]]

local function bounded(measured: string, low: number, high: number, path: string): (string, string)
	if low == high then
		return `{measured} ~= {low}`, `{path}: expected {low} bytes`
	end

	local condition: string = low > 0 and `{measured} < {low} or {measured} > {high}` or `{measured} > {high}`
	return condition, `{path}: length out of range`
end

--[[
    A @delta event's struct, walked field by field and never through a
    pair the struct has: one flag bit per field, set from the mask the
    writer is handed, and each field a block of its own under its bit on
    both sides, read into a bare local assigned inside its branch.
    Returns the name the writer takes the value by, the reader's flag
    word, the table of what was read and the fields' names, in order
--]]

function Replication.delta(self: Emit, node: Type, write: Block, read: Block): (string, string, string, string)
	local fields: { Field } = (Sizes.resolved(node) :: any).fields
	local value: string = write:name("value")
	local path: string = write.path
	local word: string = ""
	local parts: { string } = {}
	local names: { string } = {}

	self:shape(write, value, "table", path)
	self._known = false

	write:flags(#fields)
	read:flags(#fields)

	for _, field: Field in fields do
		local built: string, bit: number = write:flag()
		local flag: number = 2 ^ bit
		local result: string = read:name(field.name)
		local fieldPath: string = `{path}.{field.name}`

		word = read:flag()
		write:line(`{built} += bit32.band(mask, {flag})`)
		read:line(`local {result}: {Types.annotation(field.type)}`)
		write:open(`if bit32.btest(mask, {flag}) then`)
		read:open(`if bit32.btest({word}, {flag}) then`)

		local place: string = `{value}.{field.name}`
		self:nested(field.type, write:child(fieldPath), read:child(fieldPath), place, field.name, fieldPath, result)

		write:close("end")
		read:close("end")
		table.insert(parts, `{field.name} = {result}`)
		table.insert(names, `"{field.name}"`)
	end

	return value, word, `\{ {table.concat(parts, ", ")} }`, `\{ {table.concat(names, ", ")} }`
end

--[[
    A @dictionary string, carried as its id among the fixed bytes. The
    writer checks it as its type would, its length on every build since
    the dictionary keeps whatever it takes, then takes its id, refused
    when the dictionary is full. The reader looks the id up, refused when
    no entry holds it, and holds the entry to the type's own bounds, and
    a text to UTF-8, since one dictionary serves every such type
--]]

function Replication.dictionary(
	self: Emit,
	target: TypeDeclaration,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local text: Type = Sizes.resolved(target.type)
	local _, low: number, high: number = Sizes.lengths((text :: any).range)
	local isText: boolean = (text :: any).utf8 == true
	local invalid: string = `{path}: invalid UTF-8`
	local id: string = write:name(`{hint}Id`)
	local readId: string = read:name(`{hint}Id`)
	local result: string = read:name(hint)
	local index: number = write:reserve(DICTIONARY_BYTES)
	local at: number = read:reserve(DICTIONARY_BYTES)
	local written: string, outside: string = bounded(`#{value}`, low, high, path)
	local stored: string = bounded(`#{result}`, low, high, path) -- The same bounds, held to the entry the id names

	self:shape(write, value, "string", path)
	refuse(write, written, outside)

	if isText and self._validate then
		refuse(write, `utf8.len({value}) == nil`, invalid)
	end

	write:line(`local {id}: number = internDictionary({value})`)
	refuse(write, `{id} == 0`, `{path}: dictionary full`)
	write:line(`buffer.writeu16({write.out}, {write:at(index)}, {id})`)

	read:line(`local {readId}: number = buffer.readu16(packet, {read:at(at)})`)
	read:line(`local {result}: string = dictionaryEntries[{readId}]`)
	refuse(read, `{result} == nil`, `{path}: unknown dictionary id`)
	refuse(read, stored, outside)

	if isText then
		refuse(read, `utf8.len({result}) == nil`, invalid)
	end

	return result
end

return Replication
