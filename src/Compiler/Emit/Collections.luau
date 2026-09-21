--[[
    The collection walks, merged onto the emitter: an array as a length
    and a run of entry blocks, an array of booleans packed as a bitset,
    a map or set as counted entries, and the run of child blocks the
    entries are walked in, which shares one allocation and one check when
    every byte of an entry sits among its block's fixed bytes
--]]

--!strict
local Collections = {} :: any

local Blocks = require("../Blocks")
local Expressions = require("./Expressions")
local Parser = require("../Parser")
local Schema = require("../Config/Types/Schema")
local Sizes = require("../Analyse/Sizes")

type Block = Blocks.Block
type Range = Schema.Range
type Region = Blocks.Region
type Size = Sizes.Size
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration

local minus = Expressions.minus
local times = Expressions.times
local group = Expressions.group
local refusal = Expressions.refusal

--[[
    Whether a type's walk puts every byte among the fixed bytes of the
    block walking it, which is what lets a run of them share one region:
    scalars, exact strings, Roblox types, unit enums and structs of those.
    A prefixed payload, a child block, a run of its own and a shared
    named type all put bytes in the tail instead
--]]

local function inline(node: Type): boolean
	if node.kind == "reference" then
		local target: TypeDeclaration = node.target :: TypeDeclaration
		return not Sizes.shared(target) and inline(target.type)
	elseif node.kind == "primitive" then
		local name: string = node.name
		return (name ~= "string" and name ~= "buffer") or Sizes.lengths(node.range) == 0
	elseif node.kind == "roblox" then
		return node.name ~= "EnumItem"
	elseif node.kind == "enum" then
		return node.tag == nil
	elseif node.kind == "union" then
		return Sizes.flattened(node.members) ~= nil
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

function Collections:array(node: Type, write: Block, read: Block, value: string, hint: string, path: string): string
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

	read:tail(`local {result} = table.create({count})`)
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

function Collections:run(
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
    a bounded one as a length and a run of bytes packed eight to a byte
--]]

function Collections:bitset(range: Range?, write: Block, read: Block, value: string, hint: string, path: string): string
	self:shape(write, value, "table", path)

	local measured: string = `#{value}`
	local count: string, prefix: number, low: number = self:length(range, write, read, measured, hint, path, "entries")
	local result: string = read:name(hint)
	local index: string = write:name("index")
	local position: string = read:name("index")

	if prefix == 0 then
		local word: string, bit: number = write:flag(low)
		local lift: string = group(minus(index, 1 - bit))
		local readLift: string = group(minus(position, 1 - bit))

		read:flag(low)
		write:line(`for {index} = 1, {count} do\n\t{word} += {value}[{index}] and 2 ^ {lift} or 0\nend`)
		read:line(`local {result}: \{ boolean } = table.create({count})`)
		read:line(`for {position} = 1, {count} do\n\t{result}[{position}] = bit32.btest({word}, 2 ^ {readLift})\nend`)

		return result
	end

	local byte: string = write:name("byte")
	local bit: string = write:name("bit")
	local packed: string = write:name("packed")

	write:extend(hint, path, `({measured} + 7) // 8`, function (out: string, offset: string): string
		local inner: string =
			`\tlocal {packed}: number = 0\n\n\tfor {bit} = 0, 7 do\n\t\t{packed} += {value}[{byte} * 8 + {bit} + 1] and 2 ^ {bit} or 0\n\tend`
		return `for {byte} = 0, ({measured} + 7) // 8 - 1 do\n{inner}\n\n\tbuffer.writeu8({out}, {offset} + {byte}, {packed})\nend`
	end)

	read:extend(hint, path, `({count} + 7) // 8`, function (source: string, offset: string): string
		local byteAt: string = `{offset} + ({position} - 1) // 8`
		local test: string = `bit32.btest(buffer.readu8({source}, {byteAt}), 2 ^ (({position} - 1) % 8))`
		return `local {result}: \{ boolean } = table.create({count})\n\nfor {position} = 1, {count} do\n\t{result}[{position}] = {test}\nend`
	end)

	return result
end

--[[
    A map or set: the entries counted for the length, then each entry in
    a run of blocks, a key and a value or an element alone; the reader
    refuses a key it has already seen
--]]

function Collections:map(node: Type, write: Block, read: Block, value: string, hint: string, path: string): string
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

	read:tail(`local {result} = \{}`)
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
