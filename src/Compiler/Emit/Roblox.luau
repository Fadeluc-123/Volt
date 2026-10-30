--[[
    The Roblox type walks, merged onto the emitter: a value built from its
    components, a ray or a region through its numeric type arguments, a
    colour as three channels, a brick colour and a typed enum item by
    number, a date by its timestamp, and an untyped item by its enum's name
    and number; CFrames and instances are siblings'
--]]

--!strict
local RobloxTypes = {}

local Blocks = require("../Blocks")
local Expressions = require("./Expressions")
local Primitives = require("../Config/Primitives")
local Print = require("../Analyse/Print")
local Roblox = require("../Config/Roblox")
local Schema = require("../Config/Types/Schema")
local Types = require("../Config/Types/Emit")
local Wire = require("../Config/Wire")

type Block = Blocks.Block
type Emit = Types.Emit
type Range = Schema.Range
type Roblox = Schema.Roblox
type Type = Schema.Type

local CHANNELS: { string } = { "R", "G", "B" }
local CORNERS: { string } = { "Min", "Max" } -- A Region3's corners, the half size taken from its centre and added

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

local refusal = Expressions.refusal
local refuse = Expressions.refuse

-- A Vector3 of a type argument, which a ray's two vectors and a region's two corners are walked as
local function vector(argument: Type?): Type
	return { kind = "roblox", name = "Vector3", generics = { argument or COMPONENT }, start = 0, finish = 0 }
end

-- Whether a number type can carry an infinity: a float with either end of its range open
local function open(node: Type): boolean
	local range: Range? = (node :: any).range
	return Primitives[(node :: any).name].float == true and not (range and range.min and range.max)
end

-- Each component of each Vector3, as the expressions that read them
local function spread(vectors: { string }): { string }
	local numbers: { string } = {}
	for _, expression: string in vectors do
		for _, axis: string in Roblox.Vector3.axes :: { string } do
			table.insert(numbers, `{expression}.{axis}`)
		end
	end

	return numbers
end

-- Refuses any of the numbers being infinite, which a number carried as an open float can be
local function infinite(block: Block, numbers: { string }, message: string)
	local terms: { string } = {}
	for _, number: string in numbers do
		table.insert(terms, `math.abs({number}) == math.huge`)
	end

	refuse(block, table.concat(terms, " or "), message)
end

--[[
    A Roblox type as its components. The writer refuses the wrong class,
    and every component is a number or string by construction, so none
    checks its own type
--]]

function RobloxTypes.roblox(
	self: Emit,
	node: Roblox,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local name: string = node.name
	local row = Roblox[name]

	if row.awaited then
		return self:awaited(node, write, read, value, hint, path)
	elseif row.classed then
		return self:instance(node, write, read, value, hint, path)
	end

	if self._validate and not self._known then
		local item: string = name == "Enum" and ` or {value}.EnumType ~= Enum.{node.item}` or ""
		refuse(write, `typeof({value}) ~= "{row.class}"{item}`, `{path}: expected {Print.type(node)}`)
	end

	local generics: { Type } = node.generics or {}
	local result: string = read:name(hint)
	local known: boolean = self._known

	-- Every walk below takes the value as its class, so a vector nested in it adds no second class check
	self._known = true

	if row.axes then
		self:components(node, write, read, value, hint, path, result)
	elseif name == "CFrame" then
		self:cframe(node, write, read, value, hint, path, result)
	elseif name == "Ray" then
		local origin: string =
			self:type(vector(generics[1]), write, read, `{value}.Origin`, `{hint}Origin`, `{path}.Origin`)
		local direction: string =
			self:type(vector(generics[2]), write, read, `{value}.Direction`, `{hint}Direction`, `{path}.Direction`)

		read:line(`local {result}: Ray = Ray.new({origin}, {direction})`)
	elseif name == "Region3" then
		self:corners(node, write, read, value, hint, path, result)
	elseif row.rotation then
		self:rotated(node, write, read, value, hint, path, result)
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
				`for _, item: Enum.{item} in Enum.{item}:GetEnumItems() do\n\t{constant}[item.Value] = item\nend`
			return `local {constant}: \{ [number]: Enum.{item} } = \{}\n{fill}`
		end)

		local index: number = write:reserve(2)
		local at: number = read:reserve(2)

		write:line(`buffer.writeu16({write.out}, {write:at(index)}, {value}.Value)`)
		read:line(`local {result}: Enum.{item}? = {items}[buffer.readu16(packet, {read:at(at)})]`)

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
    A value built from the components its row names, each a property
    path carried as the type argument the row gives it, then rebuilt with
    its constructor. A range's reader refuses a minimum above its maximum,
    and a rectangle of an open float is refused when a component is
    infinite, by a writer that checks and by every reader
--]]

function RobloxTypes.components(
	self: Emit,
	node: Roblox,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string,
	result: string
)
	local name: string = node.name
	local row = Roblox[name]
	local generics: { Type } = node.generics or {}
	local arguments: { number } = row.arguments or {}
	local finite: boolean = name == "Rect" and open(generics[1] or COMPONENT)
	local checked: { string } = {}
	local parts: { string } = {}

	for index: number, axis: string in row.axes :: { string } do
		local bare: string = axis:gsub("%.", "")
		local place: string = `{value}.{axis}`

		-- A component the writer checks for infinity is read into the local the walk would give it, to check it there
		if finite and self._validate then
			place = write:name(`{hint}{bare}`)
			write:line(`local {place} = {value}.{axis}`)
			table.insert(checked, place)
		end

		local component: Type = generics[arguments[index] or 1] or COMPONENT
		table.insert(parts, self:type(component, write, read, place, `{hint}{bare}`, `{path}.{axis}`))
	end

	if #checked > 0 then
		infinite(write, checked, `{path}: expected {Print.type(node)}`)
	end

	if finite then
		infinite(read, parts, `{path}: out of range`)
	elseif name == "NumberRange" then
		refuse(read, `{parts[1]} > {parts[2]}`, `{path}: out of range`)
	end

	read:line(`local {result}: {name} = {name}.new({table.concat(parts, ", ")})`)
end

--[[
    A Region3 as its two corners, its centre less and plus half its size,
    each walked as a Vector3 of the type argument and rebuilt with
    Region3.new. Corners of an open float are refused when a component is
    infinite, by a writer that checks and by every reader
--]]

function RobloxTypes.corners(
	self: Emit,
	node: Roblox,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string,
	result: string
)
	local argument: Type? = (node.generics or {})[1]
	local finite: boolean = open(argument or COMPONENT)
	local written: { string } = {}
	local corners: { string } = {}

	for index: number, corner: string in CORNERS do
		local name: string = write:name(`{hint}{corner}`)
		local sign: string = index == 1 and "-" or "+"

		write:line(`local {name} = {value}.CFrame.Position {sign} {value}.Size / 2`)
		table.insert(written, name)
	end

	-- Checked before either corner is walked, since an infinite corner makes the other's component NaN
	if finite and self._validate then
		infinite(write, spread(written), `{path}: expected {Print.type(node)}`)
	end

	for index: number, corner: string in CORNERS do
		local walked: string =
			self:type(vector(argument), write, read, written[index], `{hint}{corner}`, `{path}.{corner}`)
		table.insert(corners, walked)
	end

	if finite then
		infinite(read, spread(corners), `{path}: out of range`)
	end

	read:line(`local {result}: Region3 = Region3.new({table.concat(corners, ", ")})`)
end

return RobloxTypes
