--[[
    The CFrame walks, merged onto the emitter: a CFrame as its position and
    its rotation as the axis times the angle, one rotation component scaled
    for an integer type, and a rotation-first CFrame as its rotation's
    bytes and its position
--]]

--!strict
local Frames = {}

local Blocks = require("../Blocks")
local Expressions = require("./Expressions")
local Primitives = require("../Config/Primitives")
local Roblox = require("../Config/Roblox")
local Schema = require("../Config/Types/Schema")
local Types = require("../Config/Types/Emit")
local Wire = require("../Config/Wire")

type Block = Blocks.Block
type Emit = Types.Emit
type Range = Schema.Range
type Roblox = Schema.Roblox
type Type = Schema.Type

local TURN: string = "2 * math.pi" -- The span an integer rotation component is scaled from

-- The primitive a CFrame's numbers are carried as when it names none, as the node the walk takes
local COMPONENT: Type = { kind = "primitive", name = Wire.component, start = 0, finish = 0 }

local minus = Expressions.minus
local plus = Expressions.plus
local group = Expressions.group
local refuse = Expressions.refuse
local writeNumber = Expressions.writeNumber
local readNumber = Expressions.readNumber

--[[
    A CFrame as a position and a rotation vector, the axis times the
    angle, each component carried as the named numeric type
--]]

function Frames.cframe(
	self: Emit,
	node: Roblox,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string,
	result: string
)
	local generics: { Type } = node.generics or {}
	local position: Type = generics[1] or COMPONENT
	local rotation: Type = generics[2] or COMPONENT
	local axis: string = write:name(`{hint}Axis`)
	local angle: string = write:name(`{hint}Angle`)
	local axes: { string } = Roblox.Vector3.axes :: { string }
	local parts: { string } = {}

	for _, component: string in axes do
		local place: string = `{value}.{component}`
		table.insert(parts, self:type(position, write, read, place, `{hint}{component}`, `{path}.{component}`))
	end

	self.helpers.cframe = true
	write:line(`local {axis}: Vector3, {angle}: number = axisAngle({value})`)

	for _, component: string in axes do
		local turn: string = `{axis}.{component} * {angle}`
		local turnHint: string = `{hint}Rotation{component}`
		table.insert(parts, self:turn(rotation, write, read, turn, turnHint, `{path}.Rotation.{component}`))
	end

	read:line(`local {result}: CFrame = cframe({table.concat(parts, ", ")})`)
end

--[[
    One rotation component: a float or quantised type carries the value as
    it is, an integer type scales it from a whole turn onto its range on
    the way out and back on the way in
--]]

function Frames.turn(
	self: Emit,
	node: Type,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local name: string = (node :: any).name
	local row = Primitives[name]
	local floor: number? = row.min
	local ceiling: number? = row.max

	if not floor or not ceiling then
		return self:type(node, write, read, value, hint, path)
	end

	local range: Range? = (node :: any).range
	local low: number = range and range.min or floor
	local span: number = (range and range.max or ceiling) - low
	local index: number = write:reserve(row.bytes :: number)
	local at: number = read:reserve(row.bytes :: number)
	local result: string = read:name(hint)

	writeNumber(write, name, index, `math.round({plus(low, `({value} + math.pi) / ({TURN}) * {span}`)})`)
	read:line(`local {result}: number = {readNumber(read, name, at)}`)

	return `{group(minus(result, low))} / {span} * ({TURN}) - math.pi`
end

--[[
    A rotation-first CFrame: its rotation in the row's bytes, then the
    position. An aligned one is a byte naming one of the 24 rotations, a
    quaternion one the smallest three components in a u32. A rotation the
    bytes cannot carry, one not aligned or one with no finite quaternion,
    is refused on every build
--]]

function Frames.rotated(
	self: Emit,
	node: Roblox,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string,
	result: string
)
	local position: Type = (node.generics or {})[1] or COMPONENT
	local aligned: boolean = node.name == "AlignedCFrame"
	local width: string = aligned and "u8" or "u32"
	local bytes: number = Roblox[node.name].rotation :: number
	local index: string = write:name(`{hint}Rotation`)
	local rotation: string = read:name(`{hint}Rotation`)
	local reserved: number = write:reserve(bytes)
	local at: number = read:reserve(bytes)
	local packed: string = readNumber(read, width, at)
	local parts: { string } = {}

	-- A rotation the bytes cannot carry takes -1, so the local is a number the checker can follow
	if aligned then
		self.helpers.aligned = true
		write:line(`local {index}: number = alignedIndex({value}) or -1`)
		refuse(write, `{index} < 0`, `{path}: expected an axis-aligned rotation`)
	else
		self.helpers.quaternion = true
		write:line(`local {index}: number = packQuaternion({value})`)
		refuse(write, `{index} < 0`, `{path}: expected a rotation`)
	end

	writeNumber(write, width, reserved, index)

	local rebuilt: string = aligned and `ALIGNED[{packed} + 1]` or `unpackQuaternion({packed})`

	read:line(`local {rotation}: CFrame? = {rebuilt}`)
	refuse(read, `not {rotation}`, `{path}: out of range`)

	for _, component: string in Roblox.Vector3.axes :: { string } do
		local place: string = `{value}.{component}`
		table.insert(parts, self:type(position, write, read, place, `{hint}{component}`, `{path}.{component}`))
	end

	read:line(`local {result}: CFrame = {rotation} + Vector3.new({table.concat(parts, ", ")})`)
end

return Frames
