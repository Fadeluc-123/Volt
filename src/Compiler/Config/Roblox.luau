--[[
    Every Roblox type the schema language names, one row each: what typeof
    reports for it, its numeric type arguments, its components and the
    argument each is carried as, a rotation-first CFrame's rotation bytes,
    fixed bytes, side-array slots, whether it takes a class, and whether
    the client waits for it by an id
--]]

--!strict
export type Roblox = {
	class: string, -- What typeof reports for a value
	generics: number?, -- Numeric type arguments the type takes
	axes: { string }?, -- The components a value is built from, in its constructor's order, each a property path
	arguments: { number }?, -- The type argument each component is carried as, the first when absent
	rotation: number?, -- Bytes a rotation-first CFrame's rotation takes, before a position of three type arguments
	bytes: number?, -- Fixed bytes for a type carried without components
	slots: number?, -- Side-array slots for a type carried outside the buffer
	classed: boolean?, -- Takes a class in parentheses, which its instance must be
	awaited: boolean?, -- Sent as an id the client waits on until the instance has arrived
}

local Roblox: { [string]: Roblox } = {
	Vector3 = { class = "Vector3", generics = 1, axes = { "X", "Y", "Z" } },
	Vector2 = { class = "Vector2", generics = 1, axes = { "X", "Y" } },
	CFrame = { class = "CFrame", generics = 2 }, -- The position, then the rotation
	AlignedCFrame = { class = "CFrame", generics = 1, rotation = 1 }, -- An index into the 24 aligned rotations
	QuaternionCFrame = { class = "CFrame", generics = 1, rotation = 4 }, -- The smallest three quaternion components
	Color3 = { class = "Color3", bytes = 3 },
	BrickColor = { class = "BrickColor", bytes = 2 },
	DateTime = { class = "DateTime", bytes = 8 },
	DateTimeMillis = { class = "DateTime", bytes = 8 },
	Instance = { class = "Instance", slots = 1, classed = true },
	StreamedInstance = { class = "Instance", slots = 1, classed = true },
	AwaitedInstance = { class = "Instance", bytes = 4, classed = true, awaited = true }, -- The id its scope gives it
	Enum = { class = "EnumItem", bytes = 2 },
	EnumItem = { class = "EnumItem" }, -- Its enum's name as a string, then two bytes
	UDim2 = {
		class = "UDim2",
		generics = 2, -- The scale, then the offset
		axes = { "X.Scale", "X.Offset", "Y.Scale", "Y.Offset" },
		arguments = { 1, 2, 1, 2 },
	},
	NumberRange = { class = "NumberRange", generics = 1, axes = { "Min", "Max" } },
	Rect = { class = "Rect", generics = 1, axes = { "Min.X", "Min.Y", "Max.X", "Max.Y" } },
	Ray = { class = "Ray", generics = 2 }, -- The origin, then the direction, each a Vector3
	Region3 = { class = "Region3", generics = 1 }, -- Its two corners, each a Vector3
}

return Roblox
