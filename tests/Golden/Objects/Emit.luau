local allocateReliable, slotReliable = ...

-- Every enum by the name its items report, so an untyped item finds its way back
local ENUMS: { [string]: Enum } = {}
for _, enum: Enum in Enum:GetEnums() do
	ENUMS[tostring(enum)] = enum
end

--[[
    Finds an item of any enum by the enum's name and the item's value, or
    nil when either is unknown
--]]

local function enumItem(name: string, value: number): EnumItem?
	local enum: Enum? = ENUMS[name]
	if not enum then
		return nil
	end

	-- Whiteoak TODO: a scan of the enum's items per read, a table per enum if untyped items show in a profile
	for _, item: EnumItem in enum:GetEnumItems() do
		if item.Value == value then
			return item
		end
	end

	return nil
end

local MATERIAL: { [number]: EnumItem } = {}
for _, item: EnumItem in Enum.Material:GetEnumItems() do
	MATERIAL[item.Value] = item
end

local function writeObjects(a: Instance, b: BasePart, c: Instance?, d: Model, e: any, f: any?)
	local offset: number, out: buffer = allocateReliable(1)
	local flags: number = 0

	if typeof(a) ~= "Instance" then
		error("Objects.a: expected Instance")
	end

	slotReliable(a)

	if typeof(b) ~= "Instance" or not b:IsA("BasePart") then
		error("Objects.b: expected Instance(BasePart)")
	end

	slotReliable(b)
	flags += c ~= nil and 1 or 0

	if typeof(d) ~= "Instance" or not d:IsA("Model") then
		error("Objects.d: expected StreamedInstance(Model)")
	end

	slotReliable(d)
	flags += e ~= nil and 2 or 0

	if e ~= nil then
		slotReliable(e)
	end

	flags += f ~= nil and 4 or 0

	if f ~= nil then
		slotReliable(f)
	end

	buffer.writeu8(out, offset, flags)

	if c ~= nil then
		if typeof(c) ~= "Instance" then
			error("Objects.c: expected Instance")
		end

		slotReliable(c)
	end
end

local function readObjects(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	if cursor + 1 > length then
		error("Objects: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local a: Instance? = side[sideCursor]
	sideCursor += 1

	if typeof(a) ~= "Instance" then
		error("Objects.a: expected Instance")
	end

	local b: BasePart? = side[sideCursor]
	sideCursor += 1

	if typeof(b) ~= "Instance" or not b:IsA("BasePart") then
		error("Objects.b: expected Instance(BasePart)")
	end

	local c
	local d: Model? = side[sideCursor]
	sideCursor += 1

	if d ~= nil and not d:IsA("Model") then
		error("Objects.d: expected StreamedInstance(Model)")
	end

	local e: any = nil

	if bit32.btest(flags, 2) then
		e = side[sideCursor]
		sideCursor += 1

		if e == nil then
			error("Objects.e: missing")
		end
	end

	local f: any = nil

	if bit32.btest(flags, 4) then
		f = side[sideCursor]
		sideCursor += 1

		if f == nil then
			error("Objects.f: missing")
		end
	end

	cursor += 1

	if bit32.btest(flags, 1) then
		local c_2: Instance? = side[sideCursor]
		sideCursor += 1

		if typeof(c_2) ~= "Instance" then
			error("Objects.c: expected Instance")
		end

		c = c_2
	end

	return cursor, sideCursor, a, b, c, d, e, f
end

local function writeItems(a: Enum.Material, b: EnumItem)
	local offset: number, out: buffer = allocateReliable(5)

	if typeof(a) ~= "EnumItem" or a.EnumType ~= Enum.Material then
		error("Items.a: expected Enum.Material")
	end

	buffer.writeu16(out, offset, a.Value)

	if typeof(b) ~= "EnumItem" then
		error("Items.b: expected EnumItem")
	end

	local bName: string = tostring(b.EnumType)

	if #bName < 1 or #bName > 255 then
		error("Items.b.EnumType: length out of range")
	end

	buffer.writeu8(out, offset + 2, #bName - 1)
	buffer.writeu16(out, offset + 3, b.Value)
	local bNameOffset: number, bNameOut: buffer = allocateReliable(#bName)
	buffer.writestring(bNameOut, bNameOffset, bName)
end

local function readItems(packet: buffer, cursor: number, _, sideCursor: number, length: number)
	if cursor + 5 > length then
		error("Items: truncated")
	end

	local a: EnumItem? = MATERIAL[buffer.readu16(packet, cursor)]

	if not a then
		error("Items.a: out of range")
	end

	local bNameLength: number = 1 + buffer.readu8(packet, cursor + 2)

	if bNameLength > 255 then
		error("Items.b.EnumType: length out of range")
	end

	local bValue: number = buffer.readu16(packet, cursor + 3)
	cursor += 5

	if cursor + bNameLength > length then
		error("Items.b.EnumType: truncated")
	end

	local bName: string = buffer.readstring(packet, cursor, bNameLength)
	cursor += bNameLength
	local b: EnumItem? = enumItem(bName, bValue)

	if not b then
		error("Items.b: out of range")
	end

	return cursor, sideCursor, a, b
end

return {
	Objects = { write = writeObjects, read = readObjects },
	Items = { write = writeItems, read = readItems },
}
