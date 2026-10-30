--[[
    Proves UDim2, NumberRange, Rect, Ray and Region3: their sizes, the type
    arguments and class each takes, the top-level type names they keep for
    themselves, their canonical form, a region of negative size read back
    with it, and their names reserved from the generated code's locals
--]]

--!strict
local fs = require("@lune/fs")

local Suite = require("./Suite")
local Environment = require("./Environment")
local Families = require("./Families")
local Generated = require("./Generated")
local rendered = require("./Rendered")
local Print = require("@volt/Compiler/Analyse/Print")
local Reserved = require("@volt/Compiler/Config/Reserved")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Sizes = require("@volt/Compiler/Analyse/Sizes")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

local Region3 = Environment.Region3
local Vector3 = Environment.Vector3

local LAYOUTS: string = fs.readFile("tests/Schemas/Layouts.volt")
local VOLUMES: string = fs.readFile("tests/Schemas/Volumes.volt")
local NAMES: { string } = { "UDim2", "NumberRange", "Rect", "Ray", "Region3" }

-- Each form with the bytes it takes, at its least and its most alike
local SIZES: { { any } } = {
	{ "UDim2", 16 },
	{ "UDim2<q16(0..1), i16>", 8 },
	{ "NumberRange", 8 },
	{ "NumberRange<u8(0..100)>", 2 },
	{ "Rect", 16 },
	{ "Ray", 24 },
	{ "Ray<i16(-2048..2048), q16(-512..512)>", 12 },
	{ "Region3", 24 },
	{ "Region3<q16(-4096..4096)>", 12 },
}

-- Each wrong use of a type's arguments or class: the type, where V3007 points and what it says
local MISUSES: { { string } } = {
	{ "UDim2<f32>", "UDim2<f32>", "UDim2 takes two numeric type arguments, got 1" },
	{ "Rect<f32, f32>", "Rect<f32, f32>", "Rect takes one numeric type argument, got 2" },
	{ "NumberRange<string>", "string", "NumberRange's type argument must be a numeric primitive, got string" },
	{ "Ray(Model)", "Ray(Model)", "Ray takes no class" },
}

local least = Families.least

describe("Datatypes", function ()
	for _, row: { any } in SIZES do
		test(`{row[1]} takes {row[2]} bytes and nothing else`, function ()
			local file: Schema.File = Generated.compile("Test", `{LAYOUTS}\ntype T = {row[1]}`)
			local declaration: Schema.TypeDeclaration = file.declarations[#file.declarations] :: Schema.TypeDeclaration
			local size: Sizes.Size = Sizes.size(declaration.type)

			expect(`{size.min} {size.max} {size.bits} {size.slots}`).is(`{row[2]} {row[2]} 0 0`)
		end)
	end

	for _, misuse: { string } in MISUSES do
		test(`{misuse[1]} is V3007: {misuse[3]}`, function ()
			local text: string = `{LAYOUTS}\ntype T = {misuse[1]}`
			local ok: boolean, message: any = pcall(Generated.compile, "Test", text)
			local expected: string = rendered(text, misuse[2], `error V3007: {misuse[3]}`)

			expect(ok).is(false)
			expect(tostring(message):find(expected, 1, true) ~= nil).is(true)
		end)
	end

	test("keeps each name from a top-level type, which no reference could reach", function ()
		for _, name: string in NAMES do
			local ok: boolean, message: any = pcall(Generated.modules, "Test", `{LAYOUTS}\ntype {name} = u8`)

			expect(ok).is(false)
			expect(tostring(message):find(`error V4002: "{name}" is a type`, 1, true) ~= nil).is(true)
		end
	end)

	test("prints its type arguments as written in the canonical form", function ()
		local layouts: string = Print.file((Generated.compile("Layouts", LAYOUTS)))
		local volumes: string = Print.file((Generated.compile("Volumes", VOLUMES)))

		expect(layouts:find("b: UDim2<q16(0..1), i16>,", 1, true) ~= nil).is(true)
		expect(volumes:find("b: Ray<i16(-2048..2048), q16(-512..512)>,", 1, true) ~= nil).is(true)
	end)

	test("reads a region of negative size back with that size", function ()
		local module: any, packet: () -> (buffer, { any }) = Generated.load("Volumes", Families.texts.Volumes)
		local written: { any } = least("Volumes", "Volumes")

		written[3] = Region3.new(Vector3.new(4, 2, 8), Vector3.zero)
		module.Volumes.write(table.unpack(written, 1, #written))

		local bytes: buffer, side: { any } = packet()
		local read: { any } = { module.Volumes.read(bytes, 0, side, 1, buffer.len(bytes)) }

		expect(read[5].Size).is(Vector3.new(-4, -2, -8))
		expect(read[5].CFrame.Position).is(Vector3.new(2, 1, 4))
	end)

	test("reserves each name from the generated code's locals, as a global and as a class it spells", function ()
		local missing: { string } = {}
		for _, name: string in NAMES do
			if not table.find(Reserved.generated, name) or not table.find(Reserved.types, name) then
				table.insert(missing, name)
			end
		end

		expect(table.concat(missing, ", ")).is("")
	end)
end)
