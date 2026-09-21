--[[
    Proves the emitter's output: every event of every test schema renders
    to its golden file byte for byte, every value written reads back the
    same at its bounds and at random, every writer refuses a bad value
    and every reader refuses a bad byte or an empty slot
--]]

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")

local Suite = require("./Suite")
local Environment = require("./Environment")
local Generated = require("./Generated")
local Values = require("./Values")
local Messages = require("@volt/Compiler/Targets/Messages")
local Schema = require("@volt/Compiler/Config/Types/Schema")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Event = Schema.Event
type Field = Schema.Field
type File = Schema.File

local CFrame = Environment.CFrame
local Enum = Environment.Enum
local Instance = Environment.Instance
local Vector3 = Environment.Vector3

local SCHEMAS: { string } = {
	"Numbers",
	"Scalars",
	"Roblox",
	"Frames",
	"Objects",
	"Records",
	"Optionals",
	"Enums",
	"Unions",
	"Lists",
	"Tables",
}
local ROUNDS: number = 200 -- Random values written and read back per event

local valueOf = Values.valueOf
local near = Values.near

-- Every writer refusal per schema: the event, the parameter, the bad value and the message
local REFUSALS: { [string]: { { any } } } = {
	Numbers = {
		{ "Integers", 1, 0.5, "Integers.a: expected u8" },
		{ "Integers", 2, 1000, "Integers.b: expected u16(1..999)" },
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

	Objects = {
		{ "Objects", 1, nil, "Objects.a: expected Instance" },
		{ "Objects", 2, Instance.new("Folder"), "Objects.b: expected Instance(BasePart)" },
		{ "Items", 1, Enum.KeyCode.A, "Items.a: expected Enum.Material" },
		{ "Items", 2, "Plastic", "Items.b: expected EnumItem" },
	},

	Records = {
		{ "Records", 1, 5, "Records.a: expected table" },
		{ "Records", 1, { x = 1, y = "ab", z = 1 }, "Records.a.z: expected boolean" },
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

	Lists = {
		{ "Lists", 1, table.create(9, 1), "Lists.a: length out of range" },
		{ "Lists", 2, { "ab" }, "Lists.b: expected 2 entries" },
		{ "Lists", 3, { true }, "Lists.c: expected 8 entries" },
	},

	Tables = {
		{ "Tables", 1, "x", "Tables.a: expected table" },
		{ "Tables", 4, { [1] = true }, "Tables.d: expected 3 entries" },
	},
}

describe("Emit", function ()
	local files: { [string]: File } = {}
	local texts: { [string]: string } = {}

	for _, name: string in SCHEMAS do
		files[name] = Generated.compile(name, fs.readFile(`tests/Schemas/{name}.volt`))
		texts[name] = Generated.render(files[name])
	end

	local function byName(schema: string, name: string): Event
		for _, event: Event in Generated.events(files[schema]) do
			if event.name == name then
				return event
			end
		end

		error(`no event {name} in {schema}`)
	end

	-- Every parameter of an event at its least, as a list the write takes
	local function least(schema: string, name: string): { any }
		local written: { any } = {}
		for index: number, field: Field in Messages.parameters(byName(schema, name)) do
			written[index] = valueOf(field.type, "min")
		end
		return written
	end

	local function fire(module: any, schema: string, name: string, written: { any }): (boolean, any)
		return pcall(module[name].write, table.unpack(written, 1, #Messages.parameters(byName(schema, name))))
	end

	local function failure(ok: boolean, message: any, expected: string)
		expect(ok).is(false)
		expect(tostring(message):find(expected, 1, true) ~= nil).is(true)
	end

	for _, schema: string in SCHEMAS do
		describe(schema, function ()
			local directory: string = `tests/Golden/{schema}`
			local golden: string = `{directory}/Emit.luau`
			local text: string = texts[schema]

			test("renders as the golden file", function ()
				if table.find(process.args, "--update") then
					if not fs.isDir(directory) then
						fs.writeDir(directory)
					end

					fs.writeFile(golden, text)
				end

				expect(fs.isFile(golden) and fs.readFile(golden) or "").is(text)
			end)

			describe("round trips", function ()
				local module: any, packet: () -> (buffer, { any }) = Generated.load(schema, text)

				for _, event: Event in Generated.events(files[schema]) do
					test(event.name, function ()
						local fields: { Field } = Messages.parameters(event)

						for round: number = 0, ROUNDS do
							local ends: string? = round == 0 and "min" or round == 1 and "max" or nil
							local written: { any } = {}

							for index: number, field: Field in fields do
								written[index] = valueOf(field.type, ends)
							end

							module[event.name].write(table.unpack(written, 1, #fields))

							local bytes: buffer, side: { any } = packet()
							local read: { any } = { module[event.name].read(bytes, 0, side, 1, buffer.len(bytes)) }

							expect(read[1]).is(buffer.len(bytes))
							expect(read[2]).is(#side + 1)

							for index: number, field: Field in fields do
								local message: string =
									`{event.name}.{field.name}: wrote {written[index]}, read {read[index + 2]}`
								assert(near(field.type, written[index], read[index + 2]), message)
							end
						end
					end)
				end
			end)

			describe("writers refuse", function ()
				local module: any = Generated.load(schema, text)

				for _, row: { any } in REFUSALS[schema] do
					test(row[4], function ()
						local written: { any } = least(schema, row[1])
						written[row[2]] = row[3]

						local ok: boolean, message: any = fire(module, schema, row[1], written)
						failure(ok, message, row[4])
					end)
				end
			end)
		end)
	end

	describe("with write validation off", function ()
		local loose: { [string]: any } = {}
		local checks: { [string]: number } = {}

		-- How many writers in a chunk still refuse a value by its Luau type; readers and union dispatch may ask
		local function typeChecks(text: string): number
			local found: number = 0
			for body: string in text:gmatch("local function write.-\nend\n") do
				found += body:find('typeof%b() ~= "') and 1 or 0
			end
			return found
		end

		for _, schema: string in SCHEMAS do
			local source: string = `option writeValidation = false\n{fs.readFile(`tests/Schemas/{schema}.volt`)}`
			local text: string = Generated.render((Generated.compile(schema, source)))

			loose[schema] = Generated.load(schema, text)
			checks[schema] = typeChecks(text)
		end

		test("no writer checks a value's type or range", function ()
			local written: { any } = least("Numbers", "Integers")
			written[1] = 0.5
			written[2] = 1000

			for _, schema: string in SCHEMAS do
				expect(checks[schema]).is(0)
			end

			expect((fire(loose.Numbers, "Numbers", "Integers", written))).is(true)
		end)

		test("a length outside its bounds is still refused", function ()
			local written: { any } = least("Scalars", "Bytes")
			written[1] = string.rep("x", 33)

			local ok: boolean, message: any = fire(loose.Scalars, "Scalars", "Bytes", written)
			failure(ok, message, "Bytes.name: length out of range")
		end)

		test("a nil instance is still refused", function ()
			local written: { any } = least("Objects", "Objects")
			written[1] = nil

			local ok: boolean, message: any = fire(loose.Objects, "Objects", "Objects", written)
			failure(ok, message, "Objects.a: expected Instance")
		end)

		test("a value no variant or member can carry is still refused", function ()
			local written: { any } = least("Enums", "Enums")
			written[1] = "Green"

			local ok: boolean, message: any = fire(loose.Enums, "Enums", "Enums", written)
			failure(ok, message, "Team: expected enum { Red, Blue }")

			written = least("Unions", "Unions")
			written[1] = {}
			ok, message = fire(loose.Unions, "Unions", "Unions", written)
			failure(ok, message, "Unions.a: expected u8 | string(0..4) | boolean")
		end)
	end)

	describe("readers refuse", function ()
		local modules: { [string]: any } = {}
		local packets: { [string]: () -> (buffer, { any }) } = {}

		for _, schema: string in SCHEMAS do
			modules[schema], packets[schema] = Generated.load(schema, texts[schema])
		end

		-- The packet and side array of an event fired with every parameter at its least, or as given
		local function packetOf(schema: string, name: string, written: { any }?): (buffer, { any })
			assert(fire(modules[schema], schema, name, written or least(schema, name)))
			return packets[schema]()
		end

		local function refused(
			schema: string,
			name: string,
			bytes: buffer,
			side: { any },
			length: number,
			expected: string
		)
			local ok: boolean, message: any = pcall(modules[schema][name].read, bytes, 0, side, 1, length)
			failure(ok, message, expected)
		end

		-- Every byte-level refusal: the schema, the event, the offset, the bytes to write there and the message
		local BYTES: { { any } } = {
			{ "Numbers", "Integers", 1, "u16", 1000, "Integers.b: out of range" },
			{ "Numbers", "Floats", 2, "f32", 0 / 0, "Floats.b: out of range" },
			{ "Numbers", "Floats", 6, "f64", 2, "Floats.c: out of range" },
			{ "Scalars", "Bytes", 0, "u8", 40, "Bytes.name: length out of range" },
			{ "Roblox", "Colours", 3, "u16", 9999, "Colours.b: out of range" },
			{ "Roblox", "Colours", 5, "f64", 0 / 0, "Colours.c.UnixTimestamp: out of range" },
			{ "Frames", "Frames", 42, "u8", 24, "Frames.c: out of range" },
			{ "Objects", "Items", 0, "u16", 65535, "Items.a: out of range" },
			{ "Objects", "Items", 3, "u16", 65535, "Items.b: out of range" },
			{ "Enums", "Enums", 0, "u8", 3, "Enums.c: out of range" },
			{ "Enums", "Enums", 0, "u8", 12, "Enums.d: out of range" },
			{ "Unions", "Unions", 0, "u8", 3, "Unions.a: out of range" },
			{ "Lists", "Lists", 1, "u8", 9, "Lists.a: length out of range" },
			{ "Lists", "Lists", 2, "u8", 21, "Lists.d: length out of range" },
		}

		for _, row: { any } in BYTES do
			test(row[6], function ()
				local bytes: buffer, side: { any } = packetOf(row[1], row[2]);
				(buffer :: any)[`write{row[4]}`](bytes, row[3], row[5])
				refused(row[1], row[2], bytes, side, buffer.len(bytes), row[6])
			end)
		end

		test("a block past the packet's end", function ()
			refused("Scalars", "Value", buffer.create(1), {}, 1, "Value: truncated")
		end)

		test("a 64-bit integer past what a number holds exactly", function ()
			local bytes: buffer, side: { any } = packetOf("Numbers", "Integers")
			buffer.writeu32(bytes, 16, 1)
			buffer.writeu32(bytes, 20, 2 ^ 21)
			refused("Numbers", "Integers", bytes, side, buffer.len(bytes), "Integers.f: out of range")
		end)

		test("a payload past the packet's end", function ()
			local bytes: buffer, side: { any } = packetOf("Scalars", "Bytes")
			refused("Scalars", "Bytes", bytes, side, buffer.len(bytes) - 1, "Bytes.name: truncated")
		end)

		test("a run of entries past the packet's end", function ()
			local written: { any } = least("Lists", "Lists")
			written[1] = table.create(8, 1)

			local bytes: buffer, side: { any } = packetOf("Lists", "Lists", written)
			refused("Lists", "Lists", bytes, side, 10, "Lists.a: truncated")
		end)

		test("an empty slot where an instance must be", function ()
			local bytes: buffer = packetOf("Objects", "Objects")
			refused("Objects", "Objects", bytes, {}, buffer.len(bytes), "Objects.a: expected Instance")
		end)

		test("an instance of the wrong class, present or streamed", function ()
			local bytes: buffer, side: { any } = packetOf("Objects", "Objects")
			side[2] = Instance.new("Folder")
			refused("Objects", "Objects", bytes, side, buffer.len(bytes), "Objects.b: expected Instance(BasePart)")

			bytes, side = packetOf("Objects", "Objects")
			side[3] = Instance.new("Folder")
			refused("Objects", "Objects", bytes, side, buffer.len(bytes), "Objects.d: expected StreamedInstance(Model)")
		end)

		test("an unknown whose flag says it is there when its slot is empty", function ()
			local written: { any } = least("Objects", "Objects")
			written[5] = 1

			local bytes: buffer, side: { any } = packetOf("Objects", "Objects", written)
			side[4] = nil
			refused("Objects", "Objects", bytes, side, buffer.len(bytes), "Objects.e: missing")
		end)

		test("a key that appears twice", function ()
			local written: { any } = least("Tables", "Tables")
			written[1] = { [1] = "", [2] = "" }

			local bytes: buffer, side: { any } = packetOf("Tables", "Tables", written)
			buffer.writeu8(bytes, 5, buffer.readu8(bytes, 3))
			refused("Tables", "Tables", bytes, side, buffer.len(bytes), "Tables.a: duplicate key")
		end)
	end)
end)
