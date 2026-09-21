--[[
    Every Roblox type the schema language names, one row each: what typeof
    reports for a value of it, how many numeric type arguments it takes,
    the components a vector carries, the fixed bytes a type with no
    components takes, and the side-array slots an instance fills
--]]

--!strict
export type Roblox = {
	class: string, -- What typeof reports for a value
	generics: number?, -- Numeric type arguments the type takes
	axes: { string }?, -- The components a vector carries, each as the numeric type argument
	bytes: number?, -- Fixed bytes for a type carried without components
	slots: number?, -- Side-array slots for a type carried outside the buffer
}

local Roblox: { [string]: Roblox } = {
	Vector3 = { class = "Vector3", generics = 1, axes = { "X", "Y", "Z" } },
	Vector2 = { class = "Vector2", generics = 1, axes = { "X", "Y" } },
	CFrame = { class = "CFrame", generics = 2 }, -- The position, then the rotation
	AlignedCFrame = { class = "CFrame", generics = 1 },
	Color3 = { class = "Color3", bytes = 3 },
	BrickColor = { class = "BrickColor", bytes = 2 },
	DateTime = { class = "DateTime", bytes = 8 },
	DateTimeMillis = { class = "DateTime", bytes = 8 },
	Instance = { class = "Instance", slots = 1 },
	StreamedInstance = { class = "Instance", slots = 1 },
	Enum = { class = "EnumItem", bytes = 2 },
	EnumItem = { class = "EnumItem" }, -- Its enum's name as a string, then two bytes
}

return Roblox
