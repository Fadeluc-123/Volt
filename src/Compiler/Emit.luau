--[[
    Walks a type once and writes its serialiser and its deserialiser into
    a pair of blocks as it goes, so both sides come from one traversal
    and cannot disagree: numbers at constant offsets with their checks,
    booleans as flag bits, strings and buffers as a prefix in the block
    and their bytes in its tail
--]]

--!strict
local Emit = {} :: any
Emit.__index = Emit

local Analyse = require("./Analyse")
local Blocks = require("./Blocks")
local Parser = require("./Parser")

type Block = Blocks.Block
type Field = Parser.Field
type Options = Parser.Options
type Pack = Parser.Pack
type Range = Parser.Range
type Type = Parser.Type

-- The wide integers, carried as a low part and a high part the library can write; a signed one lifts its high part by half
local WIDE: { [string]: { low: string, high: string, unit: number, half: number } } = {
	u24 = { low = "u8", high = "u16", unit = 256, half = 0 },
	i24 = { low = "u8", high = "u16", unit = 256, half = 2 ^ 15 },
	u48 = { low = "u16", high = "u32", unit = 65536, half = 0 },
	i48 = { low = "u16", high = "u32", unit = 65536, half = 2 ^ 31 },
	u64 = { low = "u32", high = "u32", unit = 2 ^ 32, half = 0 },
	i64 = { low = "u32", high = "u32", unit = 2 ^ 32, half = 2 ^ 31 },
}

local FLOATS: { [string]: boolean } = { f16 = true, f32 = true, f64 = true }
local LEVELS: { [string]: number } = { q8 = 255, q16 = 65535 } -- The steps a quantised range is cut into
local PREFIXES: { string } = { "u8", "u16", "u24", "u32" } -- A length prefix by its width in bytes
local EXACT_HIGH: number = 2 ^ 21 -- The high word of 2^53, the last integer a number holds exactly

--[[
    The helper functions a generated module carries when a type needs
    them, by name
--]]

Emit.HELPERS = {
	f16 = [=[
--[[
    Writes a number as an IEEE half: sign, five exponent bits and ten
    fraction bits, rounding to the nearest half and past 65504 to
    infinity
--]]

local function writef16(target: buffer, offset: number, value: number)
	local magnitude: number = math.abs(value)
	local encoded: number = 31744 -- Infinity, which anything past the largest half rounds to

	if magnitude ~= magnitude then
		encoded = 32256
	elseif magnitude < 2 ^ -14 then
		encoded = math.round(magnitude * 2 ^ 24) -- Subnormal, or zero
	elseif magnitude < 65520 then
		local fraction: number, exponent: number = math.frexp(magnitude)
		encoded = math.round((fraction * 2 - 1) * 1024) + (exponent + 14) * 1024
	end

	buffer.writeu16(target, offset, value < 0 and 32768 + encoded or encoded)
end

--[[
    Reads an IEEE half back into a number
--]]

local function readf16(source: buffer, offset: number): number
	local encoded: number = buffer.readu16(source, offset)
	local exponent: number = encoded // 1024 % 32
	local fraction: number = encoded % 1024
	local magnitude: number

	if exponent == 31 then
		magnitude = fraction == 0 and math.huge or 0 / 0
	elseif exponent == 0 then
		magnitude = fraction * 2 ^ -24
	else
		magnitude = (1 + fraction / 1024) * 2 ^ (exponent - 15)
	end

	return encoded >= 32768 and -magnitude or magnitude
end
]=],
}

function Emit.new(options: Options)
	return setmetatable({
		_validate = options.writeValidation ~= false, -- Whether writers check their values
		helpers = {} :: { [string]: boolean }, -- The helpers the walked types needed
	}, Emit)
end

-- An expression less a bound, written the way a person would
local function minus(expression: string, bound: number): string
	return bound == 0 and expression or bound < 0 and `{expression} + {-bound}` or `{expression} - {bound}`
end

-- A bound plus an expression, the bound first
local function plus(bound: number, expression: string): string
	return bound == 0 and expression or `{bound} + {expression}`
end

--[[
    The lines that refuse a value on one side when a condition holds
--]]

local function refuse(block: Block, condition: string, message: string)
	block:line(`if {condition} then\n\terror("{message}")\nend`)
end

--[[
    Writes an integer or float of one of the library's own widths, or a
    wide integer as its two parts, at a fixed offset
--]]

local function writeNumber(write: Block, name: string, index: number, value: string)
	local wide = WIDE[name]
	if not wide then
		write:line(`buffer.write{name}({write.out}, {write:at(index)}, {value})`)
		return
	end

	local high: string = plus(wide.half, `{value} // {wide.unit}`)
	write:line(`buffer.write{wide.low}({write.out}, {write:at(index)}, {value} % {wide.unit})`)
	write:line(`buffer.write{wide.high}({write.out}, {write:at(index + Analyse.BYTES[wide.low])}, {high})`)
end

--[[
    The expression that reads an integer or float back from a fixed
    offset, or the two parts of a wide integer joined
--]]

local function readNumber(read: Block, name: string, index: number): string
	local wide = WIDE[name]
	if not wide then
		return `buffer.read{name}(packet, {read:at(index)})`
	end

	local low: string = `buffer.read{wide.low}(packet, {read:at(index)})`
	local high: string = `buffer.read{wide.high}(packet, {read:at(index + Analyse.BYTES[wide.low])})`
	local lifted: string = wide.half == 0 and high or `({minus(high, wide.half)})`

	return `{low} + {lifted} * {wide.unit}`
end

--[[
    Emits one block's worth of a type into both sides: the flag bytes the
    block needs are reserved first, then the type is walked. A pack walks
    each parameter under its own name; anything else is one value.
    Returns the names the write side takes its values by and the
    expressions the read side yields them as
--]]

function Emit:block(node: Type | Pack, write: Block, read: Block): ({ string }, { string })
	local bits: number = Analyse.size(node).bits
	local names: { string } = {}
	local values: { string } = {}

	write:flags(bits)
	read:flags(bits)

	if node.kind ~= "pack" then
		local name: string = write:name("value")
		return { name }, { self:type(node, write, read, name, "value", write.path) }
	end

	-- Every parameter takes its name before any walk claims a helper local
	for _, parameter: Field in node.parameters do
		table.insert(names, write:name(parameter.name))
	end

	for index: number, parameter: Field in node.parameters do
		local path: string = `{write.path}.{parameter.name}`
		table.insert(values, self:type(parameter.type, write, read, names[index], parameter.name, path))
	end

	return names, values
end

--[[
    Walks one type on both sides. value is the write side's expression
    for it, hint names the read side's local, path names it in a failure
--]]

function Emit:type(node: Type, write: Block, read: Block, value: string, hint: string, path: string): string
	if node.kind == "reference" and node.target then
		return self:type(node.target.type, write, read, value, hint, path)
	elseif node.kind ~= "primitive" then
		-- Whiteoak TODO: Roblox types, composites and shared named types follow in the next roadmap step
		error(`{path}: {node.kind} is not generated yet`)
	elseif node.name == "boolean" then
		return self:boolean(write, read, value, path)
	elseif node.name == "string" or node.name == "buffer" then
		return self:bytes(node, write, read, value, hint, path)
	elseif LEVELS[node.name] then
		return self:quantised(node, write, read, value, hint, path)
	end

	return self:number(node, write, read, value, hint, path)
end

--[[
    An integer or float at a constant offset. The writer refuses the
    wrong Luau type, a fraction on an integer, NaN, and anything outside
    the range; the reader refuses NaN and anything outside a declared
    range, and a 64-bit value a number cannot hold exactly
--]]

function Emit:number(node: Type, write: Block, read: Block, value: string, hint: string, path: string): string
	local name: string = (node :: any).name
	local range: Range? = (node :: any).range
	local bounds: { number }? = Analyse.BOUNDS[name]
	local index: number = write:reserve(Analyse.BYTES[name])
	local at: number = read:reserve(Analyse.BYTES[name])

	local low: number? = range and range.min or bounds and bounds[1]
	local high: number? = range and range.max or bounds and bounds[2]

	if self._validate then
		local shape: string = FLOATS[name] and `{value} ~= {value}` or `{value} % 1 ~= 0`
		local terms: { string } = { `typeof({value}) ~= "number"`, shape }

		if low then
			table.insert(terms, `{value} < {low}`)
		end

		if high then
			table.insert(terms, `{value} > {high}`)
		end

		refuse(write, table.concat(terms, " or "), `{path}: expected {Analyse.printType(node)}`)
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
	elseif Analyse.BYTES[name] == 8 and not FLOATS[name] then
		self:exact(read, name, at, result, path)
	else
		read:line(`local {result}: number = {readNumber(read, name, at)}`)
	end

	if FLOATS[name] then
		table.insert(terms, `{result} ~= {result}`)
	end

	-- Only a declared end that narrows the primitive's own bound needs a check
	if range and range.min and (not bounds or range.min > bounds[1]) then
		table.insert(terms, `{result} < {range.min}`)
	end

	if range and range.max and (not bounds or range.max < bounds[2]) then
		table.insert(terms, `{result} > {range.max}`)
	end

	if #terms > 0 then
		refuse(read, table.concat(terms, " or "), `{path}: out of range`)
	end

	return result
end

--[[
    Reads a 64-bit integer as its two words and refuses one past the
    magnitude a number holds exactly before joining them
--]]

function Emit:exact(read: Block, name: string, at: number, result: string, path: string)
	local wide = WIDE[name]
	local low: string = read:name(`{result}Low`)
	local high: string = read:name(`{result}High`)
	local magnitude: string = wide.half > 0 and `math.abs({high})` or high

	read:line(`local {low}: number = buffer.readu32(packet, {read:at(at)})`)
	read:line(`local {high}: number = {minus(`buffer.readu32(packet, {read:at(at + 4)})`, wide.half)}`)

	refuse(read, `{magnitude} > {EXACT_HIGH} or {magnitude} == {EXACT_HIGH} and {low} > 0`, `{path}: out of range`)
	read:line(`local {result}: number = {low} + {high} * {wide.unit}`)
end

--[[
    A quantised float: clamped into its range and rounded onto the
    steps a byte or two hold, then stretched back out on the read side
--]]

function Emit:quantised(node: Type, write: Block, read: Block, value: string, hint: string, path: string): string
	local name: string = (node :: any).name
	local range: Range = (node :: any).range
	local min: number = range.min :: number
	local max: number = range.max :: number
	local levels: number = LEVELS[name]
	local width: string = levels == 255 and "u8" or "u16"
	local index: number = write:reserve(Analyse.BYTES[name])
	local at: number = read:reserve(Analyse.BYTES[name])

	if self._validate then
		refuse(write, `typeof({value}) ~= "number" or {value} ~= {value}`, `{path}: expected {Analyse.printType(node)}`)
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

function Emit:boolean(write: Block, read: Block, value: string, path: string): string
	local word: string, bit: number = write:flag()
	local mask: number = 2 ^ bit

	read:flag()

	if self._validate then
		refuse(write, `typeof({value}) ~= "boolean"`, `{path}: expected boolean`)
	end

	write:line(`{word} += {value} and {mask} or 0`)

	return `bit32.btest({word}, {mask})`
end

--[[
    A string or buffer. An exact length sits among the fixed bytes with
    no prefix; otherwise the prefix carries the length above the minimum
    and the bytes follow in the tail. Both sides refuse a length outside
    the bounds on every build, because a wrong prefix corrupts every byte
    after it
--]]

function Emit:bytes(node: Type, write: Block, read: Block, value: string, hint: string, path: string): string
	local isBuffer: boolean = (node :: any).name == "buffer"
	local prefix: number, low: number, high: number = Analyse.prefix((node :: any).range)
	local measured: string = isBuffer and `buffer.len({value})` or `#{value}`
	local luauType: string = isBuffer and "buffer" or "string"
	local result: string = read:name(hint)

	if self._validate then
		refuse(write, `typeof({value}) ~= "{luauType}"`, `{path}: expected {luauType}`)
	end

	local function pack(target: string, offset: string): string
		return isBuffer and `buffer.copy({target}, {offset}, {value})`
			or `buffer.writestring({target}, {offset}, {value})`
	end

	local function unpack(source: string, offset: string, count: string): string
		if not isBuffer then
			return `local {result}: string = buffer.readstring({source}, {offset}, {count})`
		end
		return `local {result}: buffer = buffer.create({count})\nbuffer.copy({result}, 0, {source}, {offset}, {count})`
	end

	if prefix == 0 then
		refuse(write, `{measured} ~= {low}`, `{path}: expected {low} bytes`)

		local index: number = write:reserve(low)
		local at: number = read:reserve(low)

		write:line(pack(write.out, write:at(index)))
		read:line(unpack("packet", read:at(at), tostring(low)))

		return result
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

	write:extend(hint, path, measured, pack)

	read:extend(hint, path, count, function (source: string, offset: string): string
		return unpack(source, offset, count)
	end)

	return result
end

return Emit
