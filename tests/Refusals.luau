--[[
    Every writer refusal of every type family, by schema: the event, the
    parameter, the bad value and the message, each message read from the
    family's rendered golden
--]]

--!strict
local Environment = require("./Environment")

local CFrame = Environment.CFrame
local Enum = Environment.Enum
local Instance = Environment.Instance
local Ray = Environment.Ray
local Rect = Environment.Rect
local Region3 = Environment.Region3
local UDim2 = Environment.UDim2
local Vector3 = Environment.Vector3

local TWO_CHARACTERS: string = utf8.char(0x65E5, 0x672C) -- Six bytes in two characters, past what Text's short takes
local HIT: { [string]: any } = { kind = "melee", damage = 0, version = 2, critical = false, ranked = true }

-- A Hit with one field changed
local function hit(key: string, value: any): { [string]: any }
	local changed: { [string]: any } = table.clone(HIT)
	changed[key] = value
	return changed
end

local Refusals: { [string]: { { any } } } = {
	Numbers = {
		{ "Integers", 1, 0.5, "Integers.a: expected u8" },
		{ "Integers", 1, 1.5, "Integers.a: expected u8" },
		{ "Integers", 1, -1, "Integers.a: expected u8" },
		{ "Integers", 1, 256, "Integers.a: expected u8" },
		{ "Integers", 1, 0 / 0, "Integers.a: expected u8" },
		{ "Integers", 1, math.huge, "Integers.a: expected u8" },
		{ "Integers", 1, "5", "Integers.a: expected u8" },
		{ "Integers", 2, 0, "Integers.b: expected u16(1..999)" },
		{ "Integers", 2, 1000, "Integers.b: expected u16(1..999)" },
		{ "Integers", 4, 2 ^ 32, "Integers.d: expected u32" },
		{ "Integers", 6, 2 ^ 53 + 2, "Integers.f: expected u64" },
		{ "Floats", 1, 0 / 0, "Floats.a: expected f16" },
		{ "Floats", 3, 2, "Floats.c: expected f64(0..1)" },
	},

	Scalars = {
		{ "Flags", 1, 1, "Flags.a: expected boolean" },
		{ "Bytes", 1, 5, "Bytes.name: expected string" },
		{ "Bytes", 1, string.rep("x", 33), "Bytes.name: length out of range" },
		{ "Bytes", 2, "abc", "Bytes.tag: expected 4 bytes" },
		{ "Bytes", 3, "raw", "Bytes.raw: expected buffer" },
	},

	Roblox = {
		{ "Vectors", 1, 5, "Vectors.a: expected Vector3" },
		{ "Vectors", 4, Vector3.new(0.5, 0, 0), "Vectors.d.X: expected u8" },
		{ "Colours", 2, 1004, "Colours.b: expected BrickColor" },
		{ "Colours", 3, 5, "Colours.c: expected DateTime" },
	},

	Frames = {
		{ "Frames", 3, CFrame.fromAxisAngle(Vector3.yAxis, 1), "Frames.c: expected an axis-aligned rotation" },
	},

	Rotations = {
		{ "Turn", 1, 5, "Turn.a: expected QuaternionCFrame" },
		{ "Turn", 1, CFrame.new(0, 0, 0, 0 / 0, 0, 0, 1), "Turn.a: expected a rotation" },
		{ "Turn", 2, CFrame.new(0 / 0, 0, 0), "Turn.b.X: expected q16(-512..512)" },
		{ "Turn", 3, { { at = CFrame.new(0.5, 0, 0) } }, "Turn.c[].at.X: expected i16(-1000..1000)" },
	},

	Layouts = {
		{ "Layouts", 1, 5, "Layouts.a: expected UDim2" },
		{ "Layouts", 2, UDim2.fromOffset(40000, 0), "Layouts.b.X.Offset: expected i16" },
		{ "Layouts", 3, Rect.new(0, 0, 1, 1), "Layouts.c: expected NumberRange" },
		{ "Layouts", 5, Rect.new(-math.huge, 0, 0, 0), "Layouts.e: expected Rect" },
	},

	Volumes = {
		{ "Volumes", 1, 5, "Volumes.a: expected Ray" },
		{
			"Volumes",
			2,
			Ray.new(Vector3.new(3000, 0, 0), Vector3.zero),
			"Volumes.b.Origin.X: expected i16(-2048..2048)",
		},
		{ "Volumes", 3, Region3.new(Vector3.new(-math.huge, 0, 0), Vector3.zero), "Volumes.c: expected Region3" },
	},

	Objects = {
		{ "Objects", 1, nil, "Objects.a: expected Instance" },
		{ "Objects", 2, Instance.new("Folder"), "Objects.b: expected Instance(BasePart)" },
		{ "Items", 1, Enum.KeyCode.A, "Items.a: expected Enum.Material" },
		{ "Items", 2, "Plastic", "Items.b: expected EnumItem" },
	},

	Records = {
		{ "Records", 1, 5, "Records.a: expected table" },
		{ "Records", 1, { x = 1, y = "ab", z = 1 }, "Records.a.z: expected boolean" },
		{ "Rows", 1, { { id = 1, name = 5 } }, "Rows.a[].name: expected string" },
	},

	Optionals = {
		{ "Optionals", 2, 5, "Optionals.b: expected string" },
		{ "Nested", 1, { grid = { { 1, 2 }, { 1 } } }, "Nested.grid[]: expected 2 entries" },
	},

	Enums = {
		{ "Enums", 1, "Green", "Team: expected enum { Red, Blue }" },
		{ "Enums", 3, { kind = "Jump" }, `Enums.c: expected enum "kind" \{ Move` },
	},

	Unions = {
		{ "Unions", 1, {}, "Unions.a: expected u8 | string(0..4) | boolean" },
	},

	Choices = {
		{ "Members", 1, { team = "Red", perks = {}, floor = Enum.KeyCode.A }, "Members.floor: expected Enum.Material" },
	},

	Lists = {
		{ "Lists", 1, table.create(9, 1), "Lists.a: length out of range" },
		{ "Lists", 2, { "ab" }, "Lists.b: expected 2 entries" },
		{ "Lists", 3, { true }, "Lists.c: expected 8 entries" },
	},

	Tables = {
		{ "Tables", 1, "x", "Tables.a: expected table" },
		{ "Tables", 4, { [1] = true }, "Tables.d: expected 3 entries" },
	},

	Text = {
		{ "Text", 1, TWO_CHARACTERS, "Text.short: length out of range" },
	},

	Literals = {
		{ "Hits", 1, hit("kind", "ranged"), `Hit.kind: expected "melee"` },
		{ "Hits", 2, hit("version", 3), "Hit.version: expected 2" },
		{ "Hits", 2, hit("ranked", false), "Hit.ranked: expected true" },
		{ "Choices", 1, "ranged", `Choices.tag: expected "melee"` },
		{ "Choices", 2, "other", `Choices.reason: expected "none"` },
	},

	Generics = {
		{ "Moves", 1, { first = 256, second = 0 }, "Pair<u8, u8>.first: expected u8" },
		{ "Moves", 2, { first = 0, second = -1 }, "Pair<u8, u8>.second: expected u8" },
		{ "Moves", 3, { first = 0, second = "abcde" }, "Moves.c.second: length out of range" },
		{ "Boxes", 1, { value = 256, spare = {} }, "Boxes.a.value: expected u8" },
		{ "Boxes", 1, { value = 0, spare = { 0, 0, 0 } }, "Boxes.a.spare: length out of range" },
		{ "Boxes", 2, { first = 70000, second = 0 }, "Scores.first: expected u16" },
	},
}

return Refusals
