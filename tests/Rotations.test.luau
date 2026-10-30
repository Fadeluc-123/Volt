--[[
    Proves the smallest-three rotation, QuaternionCFrame: its sizes, the
    type arguments it takes, the top-level type name it keeps for itself,
    the identity and the worked example read back exactly and every other
    rotation within 0.005 radians, a rotation with no finite quaternion
    refused at the fire whether or not writers validate, and the hash of
    every other schema unchanged
--]]

--!strict
local fs = require("@lune/fs")

local Suite = require("./Suite")
local Environment = require("./Environment")
local Families = require("./Families")
local Generated = require("./Generated")
local hex = require("./Hex")
local rendered = require("./Rendered")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Sizes = require("@volt/Compiler/Analyse/Sizes")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

local CFrame = Environment.CFrame
local Vector3 = Environment.Vector3

local ROTATIONS: string = fs.readFile("tests/Schemas/Rotations.volt")
local GOLDEN: string = "tests/Golden"
local ROUNDS: number = 200 -- Random rotations written and read back
local DRIFT: number = 0.005 -- How far a rotation may read back from the one written, in radians
local EXAMPLE: string = "00 02 08 E0 00 00 80 3F 00 00 00 40 00 00 40 40" -- The design's CFrame.new(1, 2, 3), after its id
local AXES: { any } = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }

-- Each form with the bytes it takes, at its least and its most alike
local SIZES: { { any } } = {
	{ "QuaternionCFrame", 16 },
	{ "QuaternionCFrame<q16(-512..512)>", 10 },
}

local least = Families.least
local fire = Families.fire
local failure = Families.failure

-- The angle between two rotations, in radians, the short way round
local function between(written: any, read: any): number
	local _, angle: number = (written.Rotation:Inverse() * read.Rotation):ToAxisAngle()
	return math.min(angle, 2 * math.pi - angle)
end

describe("Rotations", function ()
	local module: any, packet: () -> (buffer, { any }) = Generated.load("Rotations", Families.texts.Rotations)

	-- Turn written with a value as its first parameter and the rest at their least, its bytes and what reads back
	local function turned(value: any): (buffer, any)
		local written: { any } = least("Rotations", "Turn")
		written[1] = value

		module.Turn.write(table.unpack(written, 1, #written))

		local bytes: buffer, side: { any } = packet()
		local _, _, read: any = module.Turn.read(bytes, 0, side, 1, buffer.len(bytes))

		return bytes, read
	end

	for _, row: { any } in SIZES do
		test(`{row[1]} takes {row[2]} bytes and nothing else`, function ()
			local file: Schema.File = Generated.compile("Test", `{ROTATIONS}\ntype T = {row[1]}`)
			local declaration: Schema.TypeDeclaration = file.declarations[#file.declarations] :: Schema.TypeDeclaration
			local size: Sizes.Size = Sizes.size(declaration.type)

			expect(size.min).is(row[2])
			expect(size.max).is(row[2])
			expect(size.bits).is(0)
			expect(size.slots).is(0)
		end)
	end

	test("takes one numeric type argument and no class, as V3007 says", function ()
		local text: string = `{ROTATIONS}\ntype A = QuaternionCFrame<f32, f32>\ntype B = QuaternionCFrame(Model)`
		local ok: boolean, message: any = pcall(Generated.compile, "Test", text)
		local count: string = rendered(
			text,
			"QuaternionCFrame<f32, f32>",
			"error V3007: QuaternionCFrame takes one numeric type argument, got 2"
		)
		local class: string = rendered(text, "QuaternionCFrame(Model)", "error V3007: QuaternionCFrame takes no class")

		expect(ok).is(false)
		expect(tostring(message):find(`{count}\n\n{class}`, 1, true) ~= nil).is(true)
	end)

	test("keeps its name and AlignedCFrame's from a top-level type, which no reference could reach", function ()
		for _, name: string in { "QuaternionCFrame", "AlignedCFrame" } do
			local ok: boolean, message: any = pcall(Generated.modules, "Test", `{ROTATIONS}\ntype {name} = u8`)
			local expected: string =
				`error V4002: "{name}" is a Roblox type the schema language names and cannot name a type`

			expect(ok).is(false)
			expect(tostring(message):find(expected, 1, true) ~= nil).is(true)
		end
	end)

	test("reads the identity back exactly", function ()
		expect(select(2, turned(CFrame.new()))).is(CFrame.new())
	end)

	test("writes the design's example as the u32 0xE0080200 and the position, and reads it back exactly", function ()
		local bytes: buffer, read: any = turned(CFrame.new(1, 2, 3))

		expect(hex(buffer.fromstring(buffer.readstring(bytes, 0, 16)))).is(EXAMPLE)
		expect(read).is(CFrame.new(1, 2, 3))
	end)

	test("reads back random rotations, the 24 aligned and a half turn about each axis within 0.005 radians", function ()
		local rotations: { any } = {}

		for _ = 1, ROUNDS do
			local axis: any = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
			local random: any = CFrame.fromAxisAngle(axis, math.random() * 2 * math.pi)
			table.insert(rotations, random)
		end

		for _, right: any in AXES do
			for _, up: any in AXES do
				if right:Dot(up) == 0 then
					local aligned: any = CFrame.fromMatrix(Vector3.zero, right, up)
					table.insert(rotations, aligned)
				end
			end
		end

		for _, axis: any in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do
			local half: any = CFrame.fromAxisAngle(axis, math.pi)
			table.insert(rotations, half)
		end

		for _, rotation: any in rotations do
			local drift: number = between(rotation, select(2, turned(rotation)))
			assert(drift <= DRIFT, `{rotation} read back {drift} radians away`)
		end
	end)

	test("refuses a rotation with no finite quaternion at the fire, whether or not writers validate", function ()
		local loose: string =
			Generated.render((Generated.compile("Rotations", `option writeValidation = false\n{ROTATIONS}`)))

		for _, chunk: any in { module, (Generated.load("Rotations", loose)) } do
			local written: { any } = least("Rotations", "Turn")
			written[1] = CFrame.new(0, 0, 0, 0 / 0, 0, 0, 1)

			local ok: boolean, message: any = fire(chunk, "Rotations", "Turn", written)
			failure(ok, message, "Turn.a: expected a rotation")
		end
	end)

	test("leaves the hash of every other schema as its golden modules hold it", function ()
		for _, name: string in fs.readDir(GOLDEN) do
			local path: string = `{GOLDEN}/{name}/Client.luau`

			if fs.isFile(path) then
				local client: string = Generated.modules(name, fs.readFile(`tests/Schemas/{name}.volt`))
				expect(client:match("hash = (0x%x+)")).is(fs.readFile(path):match("hash = (0x%x+)"))
			end
		end
	end)
end)
