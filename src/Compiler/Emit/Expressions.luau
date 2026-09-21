--[[
    The expression strings the walkers join into generated lines: a bound
    taken from or added to an expression, a count of one, an expression
    grouped so a join keeps its meaning, the lines that refuse a value,
    and a number of any width written to or read from a fixed offset
--]]

--!strict
local Expressions = {}

local Blocks = require("../Blocks")
local Primitives = require("../Config/Primitives")

type Block = Blocks.Block

-- An expression less a bound, written the way a person would
function Expressions.minus(expression: string, bound: number): string
	return bound == 0 and expression or bound < 0 and `{expression} + {-bound}` or `{expression} - {bound}`
end

-- A bound plus an expression, the bound first
function Expressions.plus(bound: number, expression: string): string
	return bound == 0 and expression or `{bound} + {expression}`
end

-- A count of an expression, folded when the expression is itself a number and without the one nobody writes
function Expressions.times(count: number, expression: string): string
	local known: number? = tonumber(expression)
	if known then
		return tostring(count * known)
	end
	return count == 1 and expression or `{count} * {expression}`
end

-- An expression safe to join with an operator: parenthesised when it holds one of its own
function Expressions.group(expression: string): string
	return expression:find("[-+*/%%]") and `({expression})` or expression
end

--[[
    The lines that refuse a value on one side when a condition holds
--]]

function Expressions.refusal(condition: string, message: string): string
	local quoted: string = message:gsub('"', '\\"') -- A printed tagged enum carries its tag in quotes
	return `if {condition} then\n\terror("{quoted}")\nend`
end

function Expressions.refuse(block: Block, condition: string, message: string)
	block:line(Expressions.refusal(condition, message))
end

--[[
    Writes an integer or float of one of the library's own widths, or a
    wide integer as its two parts, at a fixed offset
--]]

function Expressions.writeNumber(write: Block, name: string, index: number, value: string)
	local row = Primitives[name]
	if not row.low then
		write:line(`buffer.write{name}({write.out}, {write:at(index)}, {value})`)
		return
	end

	local lowBytes: number = Primitives[row.low].bytes :: number
	local high: string = Expressions.plus(row.half :: number, `{value} // {row.unit}`)

	write:line(`buffer.write{row.low}({write.out}, {write:at(index)}, {value} % {row.unit})`)
	write:line(`buffer.write{row.high}({write.out}, {write:at(index + lowBytes)}, {high})`)
end

--[[
    The expression that reads an integer or float back from a fixed
    offset, or the two parts of a wide integer joined
--]]

function Expressions.readNumber(read: Block, name: string, index: number): string
	local row = Primitives[name]
	if not row.low then
		return `buffer.read{name}(packet, {read:at(index)})`
	end

	local lowBytes: number = Primitives[row.low].bytes :: number
	local low: string = `buffer.read{row.low}(packet, {read:at(index)})`
	local high: string = `buffer.read{row.high}(packet, {read:at(index + lowBytes)})`
	local lifted: string = row.half == 0 and high or `({Expressions.minus(high, row.half :: number)})`

	return `{low} + {lifted} * {row.unit}`
end

return Expressions
