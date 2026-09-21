--[[
    The Roblox type walks, merged onto the emitter: a vector or CFrame
    through its numeric type arguments, a colour as three channels, a
    brick colour and a typed enum item by number, a date by its
    timestamp, an untyped item by its enum's name and number, and an
    instance as a side-array slot
--]]

--!strict
local RobloxTypes = {} :: any

local Blocks = require("../Blocks")
local Expressions = require("./Expressions")
local Primitives = require("../Config/Primitives")
local Print = require("../Analyse/Print")
local Roblox = require("../Config/Roblox")
local Schema = require("../Config/Types/Schema")
local Wire = require("../Config/Wire")

type Block = Blocks.Block
type Range = Schema.Range
type Roblox = Schema.Roblox
type Type = Schema.Type

local CHANNELS: { string } = { "R", "G", "B" }
local TURN: string = "2 * math.pi" -- The span an integer rotation component is scaled from

-- The primitives Roblox types are carried as when they name none, as the nodes the walk takes
local COMPONENT: Type = { kind = "primitive", name = Wire.component, start = 0, finish = 0 }
local SECONDS: Type = { kind = "primitive", name = Wire.seconds, start = 0, finish = 0 }
local ENUM_NAME: Type = {
	kind = "primitive",
	name = "string",
	range = { min = 1, max = Wire.longestEnumName, start = 0, finish = 0 },
	start = 0,
	finish = 0,
}

local minus = Expressions.minus
local plus = Expressions.plus
local group = Expressions.group
local refusal = Expressions.refusal
local refuse = Expressions.refuse
local writeNumber = Expressions.writeNumber
local readNumber = Expressions.readNumber

--[[
    A Roblox type as its components. The writer refuses the wrong class,
    and every component is a number or string by construction, so none
    checks its own type
--]]

function RobloxTypes:roblox(node: Roblox, write: Block, read: Block, value: string, hint: string, path: string): string
	local name: string = node.name
	local row = Roblox[name]

	if row.slots then
		return self:instance(node, write, read, value, hint, path)
	end

	if self._validate and not self._known then
		local item: string = name == "Enum" and ` or {value}.EnumType ~= Enum.{node.item}` or ""
		refuse(write, `typeof({value}) ~= "{row.class}"{item}`, `{path}: expected {Print.type(node)}`)
	end

	local generics: { Type } = node.generics or {}
	local result: string = read:name(hint)
	local known: boolean = self._known

	self._known = true

	if row.axes then
		local parts: { string } = {}
		for _, axis: string in row.axes do
			local component: Type = generics[1] or COMPONENT
			table.insert(parts, self:type(component, write, read, `{value}.{axis}`, `{hint}{axis}`, `{path}.{axis}`))
		end

		read:line(`local {result}: {name} = {name}.new({table.concat(parts, ", ")})`)
	elseif name == "CFrame" then
		self:cframe(node, write, read, value, hint, path, result)
	elseif name == "AlignedCFrame" then
		self:aligned(node, write, read, value, hint, path, result)
	elseif name == "Color3" then
		local index: number = write:reserve(#CHANNELS)
		local at: number = read:reserve(#CHANNELS)
		local parts: { string } = {}

		for offset: number, channel: string in CHANNELS do
			local scaled: string = `math.round({value}.{channel} * {Wire.channelMax})`
			write:line(`buffer.writeu8({write.out}, {write:at(index + offset - 1)}, {scaled})`)
			table.insert(parts, `buffer.readu8(packet, {read:at(at + offset - 1)})`)
		end

		read:line(`local {result}: Color3 = Color3.fromRGB({table.concat(parts, ", ")})`)
	elseif name == "BrickColor" then
		local index: number = write:reserve(2)
		local at: number = read:reserve(2)
		local number: string = read:name(`{hint}Number`)

		write:line(`buffer.writeu16({write.out}, {write:at(index)}, {value}.Number)`)
		read:line(`local {number}: number = buffer.readu16(packet, {read:at(at)})`)
		read:line(`local {result}: BrickColor = BrickColor.new({number})`)

		refuse(read, `{result}.Number ~= {number}`, `{path}: out of range`)
	elseif name == "DateTime" or name == "DateTimeMillis" then
		local property: string = name == "DateTime" and "UnixTimestamp" or "UnixTimestampMillis"
		local stamp: string =
			self:number(SECONDS, write, read, `{value}.{property}`, `{hint}Stamp`, `{path}.{property}`)

		read:line(`local {result}: DateTime = DateTime.from{property}({stamp})`)
	elseif name == "Enum" then
		local item: string = node.item :: string
		local items: string = self:constant(`Enum.{item}`, item, function (constant: string): string
			local fill: string =
				`for _, item: EnumItem in Enum.{item}:GetEnumItems() do\n\t{constant}[item.Value] = item\nend`
			return `local {constant}: \{ [number]: EnumItem } = \{}\n{fill}`
		end)

		local index: number = write:reserve(2)
		local at: number = read:reserve(2)

		write:line(`buffer.writeu16({write.out}, {write:at(index)}, {value}.Value)`)
		read:line(`local {result}: EnumItem? = {items}[buffer.readu16(packet, {read:at(at)})]`)

		refuse(read, `not {result}`, `{path}: out of range`)
	else
		local enumName: string = write:name(`{hint}Name`)
		write:line(`local {enumName}: string = tostring({value}.EnumType)`)

		local named: string = self:bytes(ENUM_NAME, write, read, enumName, `{hint}Name`, `{path}.EnumType`)
		local index: number = write:reserve(2)
		local at: number = read:reserve(2)
		local number: string = read:name(`{hint}Value`)

		write:line(`buffer.writeu16({write.out}, {write:at(index)}, {value}.Value)`)
		read:line(`local {number}: number = buffer.readu16(packet, {read:at(at)})`)

		-- The name arrives in the tail, so the item is looked up there
		self.helpers.enums = true

		read:tail(`local {result}: EnumItem? = enumItem({named}, {number})`)
		read:tail(refusal(`not {result}`, `{path}: out of range`))
	end

	self._known = known
	return result
end

--[[
    A CFrame as a position and a rotation vector, the axis times the
    angle, each component carried as the named numeric type
--]]

function RobloxTypes:cframe(
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

function RobloxTypes:turn(node: Type, write: Block, read: Block, value: string, hint: string, path: string): string
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
    An axis-aligned CFrame: a byte naming one of the 24 rotations, then
    the position. A rotation that is not aligned has no byte to carry it,
    so it is refused on every build
--]]

function RobloxTypes:aligned(
	node: Roblox,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string,
	result: string
)
	local position: Type = (node.generics or {})[1] or COMPONENT
	local index: string = write:name(`{hint}Rotation`)
	local rotation: string = read:name(`{hint}Rotation`)
	local reserved: number = write:reserve(1)
	local at: number = read:reserve(1)
	local parts: { string } = {}

	self.helpers.aligned = true
	write:line(`local {index}: number? = alignedIndex({value})`)

	refuse(write, `not {index}`, `{path}: expected an axis-aligned rotation`)
	write:line(`buffer.writeu8({write.out}, {write:at(reserved)}, {index})`)

	read:line(`local {rotation}: CFrame? = ALIGNED[buffer.readu8(packet, {read:at(at)}) + 1]`)
	refuse(read, `not {rotation}`, `{path}: out of range`)

	for _, component: string in Roblox.Vector3.axes :: { string } do
		local place: string = `{value}.{component}`
		table.insert(parts, self:type(position, write, read, place, `{hint}{component}`, `{path}.{component}`))
	end

	read:line(`local {result}: CFrame = {rotation} + Vector3.new({table.concat(parts, ", ")})`)
end

--[[
    An instance: no bytes, one side-array slot. The writer refuses nil on
    every build, since an empty slot fails the receiver's decode, and the
    wrong class when validating; the reader refuses anything but an
    instance of the class, or for a streamed instance anything present
    that is not one
--]]

function RobloxTypes:instance(
	node: Roblox,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local class: string? = node.class
	local streamed: boolean = node.name == "StreamedInstance"
	local expected: string = `{path}: expected {Print.type(node)}`
	local result: string = read:name(hint)
	local terms: { string } = {}

	if not self._known then
		table.insert(terms, self._validate and `typeof({value}) ~= "Instance"` or `{value} == nil`)
	end

	if self._validate and class then
		table.insert(terms, `not {value}:IsA("{class}")`)
	end

	if #terms > 0 then
		refuse(write, table.concat(terms, " or "), expected)
	end

	write:line(`{write.slot}({value})`)
	read:line(`local {result}: {class or "Instance"}? = side[sideCursor]`)
	read:line("sideCursor += 1")

	if streamed and class then
		refuse(read, `{result} ~= nil and not {result}:IsA("{class}")`, expected)
	elseif not streamed then
		local isA: string = class and ` or not {result}:IsA("{class}")` or ""
		refuse(read, `typeof({result}) ~= "Instance"{isA}`, expected)
	end

	return result
end

return RobloxTypes
