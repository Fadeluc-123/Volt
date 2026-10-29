--[[
    The scalar walks, merged onto the emitter: an integer or float at a
    constant offset with its checks, a 64-bit integer read exactly, a
    quantised float, a boolean as a flag bit, a string or buffer with its
    length and a text's UTF-8 check, the length rule every counted type
    shares, a value carried outside the buffer in a side-array slot, and
    a literal, which carries nothing
--]]

--!strict
local Scalars = {}

local Blocks = require("../Blocks")
local Expressions = require("./Expressions")
local Primitives = require("../Config/Primitives")
local Print = require("../Analyse/Print")
local Schema = require("../Config/Types/Schema")
local Sizes = require("../Analyse/Sizes")
local Types = require("../Config/Types/Emit")

type Block = Blocks.Block
type Emit = Types.Emit
type Range = Schema.Range
type Type = Schema.Type

local PREFIXES: { string } = { "u8", "u16", "u24", "u32" } -- A length prefix by its width in bytes
local EXACT_HIGH: number = 2 ^ 21 -- The high word of 2^53, the last integer a number holds exactly
local MASKED_BYTES: number = 4 -- The widest unsigned integer bit32 holds, which its check masks to

local minus = Expressions.minus
local plus = Expressions.plus
local quote = Expressions.quote
local refusal = Expressions.refusal
local refuse = Expressions.refuse
local writeNumber = Expressions.writeNumber
local readNumber = Expressions.readNumber

--[[
    An integer or float at a constant offset. The writer refuses the
    wrong Luau type, a fraction on an integer, NaN, and anything outside
    the range; the reader refuses NaN and anything outside a declared
    range, and a 64-bit value a number cannot hold exactly
--]]

function Scalars.number(
	self: Emit,
	node: Type,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local name: string = (node :: any).name
	local range: Range? = (node :: any).range
	local row = Primitives[name]
	local bytes: number = row.bytes :: number
	local index: number = write:reserve(bytes)
	local at: number = read:reserve(bytes)

	if self._validate then
		self:checked(node, write, value, path)
	end

	if name == "f16" then
		self.helpers.f16 = true
		write:line(`writef16({write.out}, {write:at(index)}, {value})`)
	else
		writeNumber(write, name, index, value)
	end

	local result: string = read:name(hint)
	local terms: { string } = {}

	if name == "f16" then
		read:line(`local {result}: number = readf16(packet, {read:at(at)})`)
	elseif bytes == 8 and not row.float then
		self:exact(read, name, at, result, path)
	else
		read:line(`local {result}: number = {readNumber(read, name, at)}`)
	end

	if row.float then
		table.insert(terms, `{result} ~= {result}`)
	end

	-- Only a declared end that narrows the primitive's own bound needs a check
	if range and range.min and (not row.min or range.min > row.min) then
		table.insert(terms, `{result} < {range.min}`)
	end

	if range and range.max and (not row.max or range.max < row.max) then
		table.insert(terms, `{result} > {range.max}`)
	end

	if #terms > 0 then
		refuse(read, table.concat(terms, " or "), `{path}: out of range`)
	end

	return result
end

--[[
    The write-side check of an integer or float. An unsigned integer the
    bit32 library holds is refused in one comparison, since masking it to
    its width changes a fraction, a negative, NaN, infinity or anything
    past the width, beside only a declared end narrower than the width's;
    every other width keeps the fraction or NaN term and both its bounds
--]]

function Scalars.checked(self: Emit, node: Type, write: Block, value: string, path: string)
	local range: Range? = (node :: any).range
	local row = Primitives[(node :: any).name]
	local masked: boolean = row.min == 0 and (row.bytes :: number) <= MASKED_BYTES
	local terms: { string } = {}

	local low: number? = range and range.min or row.min
	local high: number? = range and range.max or row.max

	if not self._known then
		table.insert(terms, `type({value}) ~= "number"`)
	end

	if masked then
		table.insert(terms, `bit32.band({value}, {row.max}) ~= {value}`)
	else
		table.insert(terms, row.float and `{value} ~= {value}` or `{value} % 1 ~= 0`)
	end

	if low and not (masked and low == row.min) then
		table.insert(terms, `{value} < {low}`)
	end
	if high and not (masked and high == row.max) then
		table.insert(terms, `{value} > {high}`)
	end

	refuse(write, table.concat(terms, " or "), `{path}: expected {Print.type(node)}`)
end

--[[
    Reads a 64-bit integer as its two words and refuses one past the
    magnitude a number holds exactly before joining them
--]]

function Scalars.exact(_: Emit, read: Block, name: string, at: number, result: string, path: string)
	local row = Primitives[name]
	local half: number = row.half :: number
	local low: string = read:name(`{result}Low`)
	local high: string = read:name(`{result}High`)
	local magnitude: string = half > 0 and `math.abs({high})` or high

	read:line(`local {low}: number = buffer.readu32(packet, {read:at(at)})`)
	read:line(`local {high}: number = {minus(`buffer.readu32(packet, {read:at(at + 4)})`, half)}`)

	refuse(read, `{magnitude} > {EXACT_HIGH} or {magnitude} == {EXACT_HIGH} and {low} > 0`, `{path}: out of range`)
	read:line(`local {result}: number = {low} + {high} * {row.unit}`)
end

--[[
    A quantised float: clamped into its range and rounded onto the
    steps a byte or two hold, then stretched back out on the read side
--]]

function Scalars.quantised(
	self: Emit,
	node: Type,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local name: string = (node :: any).name
	local range: Range = (node :: any).range
	local row = Primitives[name]
	local min: number = range.min :: number
	local max: number = range.max :: number
	local levels: number = row.levels :: number
	local width: string = levels == 255 and "u8" or "u16"
	local index: number = write:reserve(row.bytes :: number)
	local at: number = read:reserve(row.bytes :: number)

	if self._validate then
		local nan: string = `{value} ~= {value}`
		local condition: string = self._known and nan or `type({value}) ~= "number" or {nan}`

		refuse(write, condition, `{path}: expected {Print.type(node)}`)
	end

	local clamped: string = `math.clamp({value}, {min}, {max})`
	local shifted: string = min == 0 and clamped or `({minus(clamped, min)})`
	local span: string = max - min == 1 and "" or ` / {max - min}`

	write:line(`buffer.write{width}({write.out}, {write:at(index)}, math.round({shifted}{span} * {levels}))`)

	local result: string = read:name(hint)
	local stretch: string = max - min == 1 and "" or ` * {max - min}`
	local stretched: string = `buffer.read{width}(packet, {read:at(at)}) / {levels}{stretch}`

	read:line(`local {result}: number = {plus(min, stretched)}`)

	return result
end

--[[
    A boolean is one flag bit: the writer sets it in the block's flags
    local, the reader tests it there, with no local of its own
--]]

function Scalars.boolean(self: Emit, write: Block, read: Block, value: string, path: string): string
	local word: string, bit: number = write:flag()
	local mask: number = 2 ^ bit

	read:flag()

	self:shape(write, value, "boolean", path)
	write:line(`{word} += {value} and {mask} or 0`)

	return `bit32.btest({word}, {mask})`
end

--[[
    A string or buffer. An exact length sits among the fixed bytes with
    no prefix; otherwise the bytes follow in the tail after their prefix.
    A text is refused when it is not UTF-8: by a writer that checks,
    after its length, and by every reader straight after the read
--]]

function Scalars.bytes(
	self: Emit,
	node: Type,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local isBuffer: boolean = (node :: any).name == "buffer"
	local isText: boolean = (node :: any).utf8 == true
	local measured: string = isBuffer and `buffer.len({value})` or `#{value}`
	local result: string = read:name(hint)
	local invalid: string = `{path}: invalid UTF-8`

	self:shape(write, value, isBuffer and "buffer" or "string", path)

	local count: string, prefix: number, low: number =
		self:length((node :: any).range, write, read, measured, hint, path, "bytes")

	if isText and self._validate then
		refuse(write, `utf8.len({value}) == nil`, invalid)
	end

	local function pack(target: string, offset: string): string
		return isBuffer and `buffer.copy({target}, {offset}, {value})`
			or `buffer.writestring({target}, {offset}, {value})`
	end

	local function unpack(source: string, offset: string): string
		if not isBuffer then
			return `local {result}: string = buffer.readstring({source}, {offset}, {count})`
		end
		return `local {result}: buffer = buffer.create({count})\nbuffer.copy({result}, 0, {source}, {offset}, {count})`
	end

	if prefix == 0 then
		local index: number = write:reserve(low)
		local at: number = read:reserve(low)

		write:line(pack(write.out, write:at(index)))
		read:line(unpack("packet", read:at(at)))

		if isText then
			refuse(read, `utf8.len({result}) == nil`, invalid)
		end

		return result
	end

	write:extend(hint, path, measured, pack)
	read:extend(hint, path, count, unpack)

	if isText then
		read:tail(refusal(`utf8.len({result}) == nil`, invalid))
	end

	return result
end

--[[
    The length of a string, buffer, array, map or set. An exact length has
    no prefix and is refused on the write side when the value's differs;
    otherwise the prefix carries the length above the minimum among the
    fixed bytes, refused outside the bounds on every build because a
    wrong prefix corrupts every byte after it. Returns the read side's
    count, the prefix width and the least length
--]]

function Scalars.length(
	_: Emit,
	range: Range?,
	write: Block,
	read: Block,
	measured: string,
	hint: string,
	path: string,
	unit: string
): (string, number, number)
	local prefix: number, low: number, high: number = Sizes.lengths(range)

	if prefix == 0 then
		refuse(write, `{measured} ~= {low}`, `{path}: expected {low} {unit}`)
		return tostring(low), prefix, low
	end

	local terms: { string } = { `{measured} > {high}` }
	if low > 0 then
		table.insert(terms, 1, `{measured} < {low}`)
	end

	refuse(write, table.concat(terms, " or "), `{path}: length out of range`)

	local stored: string = PREFIXES[prefix]
	local index: number = write:reserve(prefix)
	local at: number = read:reserve(prefix)
	local count: string = read:name(`{hint}Length`)

	writeNumber(write, stored, index, minus(measured, low))
	read:line(`local {count}: number = {plus(low, readNumber(read, stored, at))}`)

	-- A prefix that can count past the bound needs the bound checked
	if high - low < 2 ^ (prefix * 8) - 1 then
		refuse(read, `{count} > {high}`, `{path}: length out of range`)
	end

	return count, prefix, low
end

--[[
    A value carried outside the buffer: one flag bit for its presence and
    a side-array slot when present, which the reader refuses to find empty
--]]

function Scalars.unknown(_: Emit, write: Block, read: Block, value: string, hint: string, path: string): string
	local word: string, bit: number = write:flag()
	local mask: number = 2 ^ bit
	local result: string = read:name(hint)
	local missing: string = refusal(`{result} == nil`, `{path}: missing`):gsub("\n", "\n\t") -- Nested one level in

	read:flag()
	write:line(`{word} += {value} ~= nil and {mask} or 0`)
	write:line(`if {value} ~= nil then\n\t{write.slot}({value})\nend`)

	read:line(`local {result}: any = nil`)
	read:line(
		`if bit32.btest({word}, {mask}) then\n\t{result} = side[sideCursor]\n\tsideCursor += 1\n\n\t{missing}\nend`
	)

	return result
end

--[[
    A literal carries nothing: a writer that checks refuses any other
    value in one comparison, and the reader yields the value itself as a
    Luau literal wherever the walk puts it
--]]

function Scalars.literal(self: Emit, node: Type, write: Block, value: string, path: string): string
	local held: string | number | boolean = (node :: any).value
	local spelled: string = typeof(held) == "string" and quote(held) or tostring(held)

	if self._validate then
		refuse(write, `{value} ~= {spelled}`, `{path}: expected {Print.type(node)}`)
	end

	return spelled
end

return Scalars
