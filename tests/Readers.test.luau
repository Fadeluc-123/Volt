--[[
    Proves the emitter's readers refuse what a packet must not carry: a
    byte out of range, a block, payload or run past the packet's end, a
    64-bit integer a number cannot hold, an empty or wrong-class slot and
    a key that appears twice, each with the field's name
--]]

--!strict
local Suite = require("./Suite")
local Environment = require("./Environment")
local Families = require("./Families")
local Generated = require("./Generated")

local describe = Suite.describe
local test = Suite.test

local Instance = Environment.Instance

local least = Families.least
local fire = Families.fire
local failure = Families.failure

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

describe("Emit", function ()
	describe("readers refuse", function ()
		local modules: { [string]: any } = {}
		local packets: { [string]: () -> (buffer, { any }) } = {}

		for _, schema: string in Families.schemas do
			modules[schema], packets[schema] = Generated.load(schema, Families.texts[schema])
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
