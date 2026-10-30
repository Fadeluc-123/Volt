--[[
    The collection walks, merged onto the emitter: an array as a length
    and a run of entry blocks, an array of booleans packed as a bitset,
    a map or set as counted entries, and the run of child blocks the
    entries are walked in, which shares one allocation and one check when
    every byte of an entry sits among its block's fixed bytes
--]]

--!strict
local Collections = {}

local Blocks = require("../Blocks")
local EmitTypes = require("../Config/Types/Emit")
local Expressions = require("./Expressions")
local Parser = require("../Parser")
local Schema = require("../Config/Types/Schema")
local Sizes = require("../Analyse/Sizes")
local Types = require("../Targets/Types")
local Unions = require("../Analyse/Unions")

type Block = Blocks.Block
type Emit = EmitTypes.Emit
type Range = Schema.Range
type Region = Blocks.Region
type Size = Sizes.Size
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration

local BYTE_BITS: number = 8 -- Booleans packed into one byte of a bitset

local times = Expressions.times
local refusal = Expressions.refusal

--[[
    Whether a type's walk puts every byte among the fixed bytes of the
    block walking it, which is what lets a run of them share one region:
    scalars, exact strings, @dictionary strings, which are their id,
    Roblox types, unit enums, literals, which have none, and structs of
    those. A prefixed payload, a child block, a run of its own and a
    shared named type all put bytes in the tail instead
--]]

local function inline(node: Type): boolean
	if node.kind == "reference" then
		local target: TypeDeclaration = node.target :: TypeDeclaration
		return Sizes.dictionary(target) or (not Sizes.shared(target) and inline(target.type))
	elseif node.kind == "literal" then
		return true
	elseif node.kind == "primitive" then
		local name: string = node.name
		return (name ~= "string" and name ~= "buffer") or Sizes.lengths(node.range) == 0
	elseif node.kind == "roblox" then
		return node.name ~= "EnumItem"
	elseif node.kind == "enum" then
		return node.tag == nil
	elseif node.kind == "union" then
		return Unions.flattened(node.members) ~= nil
	elseif node.kind ~= "struct" then
		return false
	end

	for _, child: Type in Parser.children(node) do
		if not inline(child) then
			return false
		end
	end

	return true
end

--[[
    An array: the length, then the elements in a run of blocks, booleans
    packed as a bitset instead
--]]

function Collections.array(
	self: Emit,
	node: Type,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local element: Type = (node :: any).element
	local range: Range? = (node :: any).range

	if Sizes.isPrimitive(element, "boolean") then
		return self:bitset(range, write, read, value, hint, path)
	end

	self:shape(write, value, "table", path)
	self._known = false

	local measured: string = `#{value}`
	local count: string, prefix: number = self:length(range, write, read, measured, hint, path, "entries")
	local extent: string = prefix == 0 and count or measured -- An exact count is known on both sides
	local result: string = read:name(hint)
	local index: string = write:name("index")
	local position: string = read:name("index")
	local writeEntry: Block, readEntry: Block = self:run(write, read, hint, path, { element }, extent, count)

	-- The new checker makes table.create's entries unknown, which only the cast tells it otherwise
	local annotation: string = Types.annotation(node)
	read:tail(`local {result}: {annotation} = table.create({count}) :: {annotation}`)
	write:open(`for {index} = 1, {extent} do`)
	read:open(`for {position} = 1, {count} do`)

	local entry: string = self:type(element, writeEntry, readEntry, `{value}[{index}]`, `{hint}Entry`, `{path}[]`)

	readEntry:tail(`{result}[{position}] = {entry}`)
	writeEntry:done()
	readEntry:done()

	write:close("end")
	read:close("end")

	return result
end

--[[
    Opens the pair of child blocks a run of entries is walked in, with the
    flag bytes an entry's bits need. Entries of one fixed size take one
    allocation and one check for the whole run and fill it as a region;
    others take their own per entry, after a check that the least the run
    could need is there
--]]

function Collections.run(
	_: Emit,
	write: Block,
	read: Block,
	hint: string,
	path: string,
	nodes: { Type },
	measured: string,
	count: string
): (Block, Block)
	local size: Size = { min = 0, max = 0, bits = 0, slots = 0 }
	local fixed: boolean = true

	for _, node: Type in nodes do
		local part: Size = Sizes.size(node)

		size.min += part.min
		size.max += part.max
		size.bits += part.bits
		fixed = fixed and inline(node)
	end

	local low: number = Sizes.block(size)
	fixed = fixed and low > 0

	local writeRegion: Region? = fixed and write:region(hint, path, times(low, measured)) or nil
	local readRegion: Region? = low > 0 and read:region(hint, path, times(low, count)) or nil
	local writeEntry: Block = write:child(path, writeRegion)
	local readEntry: Block = read:child(path, fixed and readRegion or nil)

	writeEntry:flags(size.bits)
	readEntry:flags(size.bits)

	return writeEntry, readEntry
end

--[[
    An array of booleans: an exact count as bits of the block's own flags,
    one term per element with its mask; a bounded one as a length and a
    run of bytes packed eight to a byte, each byte built from eight terms
    and unpacked into eight entries, with the last partial byte read bit
    by bit
--]]

function Collections.bitset(
	self: Emit,
	range: Range?,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	self:shape(write, value, "table", path)

	local measured: string = `#{value}`
	local count: string, prefix: number, low: number = self:length(range, write, read, measured, hint, path, "entries")
	local result: string = read:name(hint)

	if prefix == 0 then
		local word: string, bit: number = write:flag(low)
		local terms: { string } = {}
		local tests: { string } = {}

		read:flag(low)

		for index: number = 1, low do
			local mask: number = 2 ^ (bit + index - 1)
			table.insert(terms, `({value}[{index}] and {mask} or 0)`)
			table.insert(tests, `\tbit32.btest({word}, {mask}),`)
		end

		if low > 0 then
			write:line(`{word} += {table.concat(terms, "\n\t+ ")}`)
		end

		read:line(`local {result}: \{ boolean } = \{{low > 0 and `\n{table.concat(tests, "\n")}\n` or ""}}`)

		return result
	end

	local byte: string = write:name("byte")
	local at: string = write:name("at")
	local packed: string = write:name("packed")
	local readByte: string = read:name("byte")
	local readAt: string = read:name("at")
	local readPacked: string = read:name("packed")
	local position: string = read:name("index")
	local terms: { string } = {}
	local stores: { string } = {}

	for bit: number = 1, BYTE_BITS do
		local mask: number = 2 ^ (bit - 1)
		table.insert(terms, `({value}[{at} + {bit}] and {mask} or 0)`)
		table.insert(stores, `{result}[{readAt} + {bit}] = bit32.btest({readPacked}, {mask})`)
	end

	write:extend(hint, path, `({measured} + 7) // 8`, function (out: string, offset: string): string
		local body: string = Blocks.paragraphs({
			`local {at}: number = {byte} * 8`,
			`local {packed}: number = {table.concat(terms, "\n\t+ ")}`,
			`buffer.writeu8({out}, {offset} + {byte}, {packed})`,
		})
		return `for {byte} = 0, ({measured} + 7) // 8 - 1 do\n{Blocks.indent(1, body)}\nend`
	end)

	read:extend(hint, path, `({count} + 7) // 8`, function (source: string, offset: string): string
		local whole: string = Blocks.paragraphs({
			`local {readPacked}: number = buffer.readu8({source}, {offset} + {readByte})`,
			`local {readAt}: number = {readByte} * 8`,
			table.unpack(stores),
		})
		local rest: string = `{offset} + ({position} - 1) // 8`
		local test: string = `bit32.btest(buffer.readu8({source}, {rest}), bit32.lshift(1, ({position} - 1) % 8))`

		return Blocks.paragraphs({
			`local {result}: \{ boolean } = table.create({count}) :: \{ boolean }`,
			`for {readByte} = 0, {count} // 8 - 1 do\n{Blocks.indent(1, whole)}\nend`,
			`for {position} = {count} // 8 * 8 + 1, {count} do\n\t{result}[{position}] = {test}\nend`,
		})
	end)

	return result
end

--[[
    A map or set: the entries counted for the length, then each entry in
    a run of blocks, a key and a value or an element alone; the reader
    refuses a key it has already seen
--]]

function Collections.map(
	self: Emit,
	node: Type,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local isSet: boolean = node.kind == "set"
	local key: Type = isSet and (node :: any).element or (node :: any).key
	local nodes: { Type } = isSet and { key } or { key, (node :: any).value }
	local measured: string = write:name(`{hint}Count`)
	local entryKey: string = write:name(`{hint}Key`)
	local entryValue: string = isSet and "" or write:name(`{hint}Value`)

	self:shape(write, value, "table", path)
	self._known = false

	write:line(`local {measured}: number = 0`)
	write:line(`for _ in {value} do\n\t{measured} += 1\nend`)

	local count: string, prefix: number = self:length((node :: any).range, write, read, measured, hint, path, "entries")
	local extent: string = prefix == 0 and count or measured -- An exact count is known on both sides
	local result: string = read:name(hint)
	local writeEntry: Block, readEntry: Block = self:run(write, read, hint, path, nodes, extent, count)

	-- Typed where it is made, or a set's entries read as boolean rather than the true its type promises
	read:tail(`local {result}: {Types.annotation(node)} = \{}`)
	write:open(isSet and `for {entryKey} in {value} do` or `for {entryKey}, {entryValue} in {value} do`)
	read:open(`for _ = 1, {count} do`)

	local keyPath: string = isSet and `{path}[]` or `{path}[key]`
	local readKey: string = self:type(key, writeEntry, readEntry, entryKey, `{hint}Key`, keyPath)
	local readValue: string = isSet and "true"
		or self:type(nodes[2], writeEntry, readEntry, entryValue, `{hint}Value`, `{path}[value]`)

	readEntry:tail(refusal(`{result}[{readKey}] ~= nil`, `{path}: duplicate key`))
	readEntry:tail(`{result}[{readKey}] = {readValue}`)
	writeEntry:done()
	readEntry:done()

	write:close("end")
	read:close("end")

	return result
end

return Collections
