--[[
    Proves the emitter's scalar output: every event in the scalar schema
    renders to the golden file byte for byte, every value written reads
    back the same at its bounds and at random, every writer refuses a
    bad value and every reader refuses a bad byte
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local Suite = require("./Suite")
local Analyse = require("@volt/Compiler/Analyse")
local Blocks = require("@volt/Compiler/Blocks")
local Diagnostics = require("@volt/Compiler/Diagnostics")
local Emit = require("@volt/Compiler/Emit")
local Lexer = require("@volt/Compiler/Lexer")
local Parser = require("@volt/Compiler/Parser")
local Resolve = require("@volt/Compiler/Resolve")
local Source = require("@volt/Compiler/Source")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Block = Blocks.Block
type Event = Parser.Event
type Field = Parser.Field
type Type = Parser.Type

local SCHEMA: string = "tests/Schemas/Scalars.volt"
local GOLDEN_DIRECTORY: string = "tests/Golden/Scalars"
local GOLDEN: string = `{GOLDEN_DIRECTORY}/Emit.luau`
local ROUNDS: number = 200 -- Random values written and read back per event
local FREE_LENGTH: number = 100 -- As long as an unbounded string or buffer gets in a test
local FLOAT_REACH: { [string]: number } = { f16 = 65504, f32 = 2 ^ 20, f64 = 2 ^ 40 } -- How far a random float goes each way
local LEVELS: { [string]: number } = { q8 = 255, q16 = 65535 }

--[[
    Runs a schema text through every stage before the emitter, refusing
    one that does not compile clean
--]]

local function compile(text: string): Parser.File
	local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(Source.new("Scalars.volt", text))
	local file: Parser.File = Parser.parse(Lexer.scan(diagnostics.source, diagnostics), diagnostics)

	Resolve.file(file, diagnostics)
	Analyse.file(file, diagnostics)
	assert(diagnostics.errors == 0, diagnostics:render())

	return file
end

local function events(file: Parser.File): { Event }
	local list: { Event } = {}
	for _, declaration in file.declarations do
		if declaration.kind == "event" then
			table.insert(list, declaration)
		end
	end
	return list
end

-- The fields a fire takes: a pack's parameters, or the one value
local function parameters(event: Event): { Field }
	local data = event.data

	if not data then
		return {}
	elseif data.kind == "pack" then
		return data.parameters
	end

	return { { name = "value", type = data, start = 0, finish = 0 } }
end

-- The primitive behind a type, through named types
local function primitive(node: Type): any
	while node.kind == "reference" and node.target do
		node = node.target.type
	end
	return node
end

-- The Luau type a value of a scalar type has
local function luauType(node: Type): string
	local name: string = primitive(node).name
	local direct: boolean = name == "boolean" or name == "string" or name == "buffer"

	return direct and name or "number"
end

--[[
    Renders every event of a file as a write function over an allocator
    and a read function over a bare buffer, the helpers they need above
    them and a table of the pairs at the end, so the text is one loadable
    chunk and one golden file
--]]

local function render(file: Parser.File): string
	local emitter = Emit.new(file.options)
	local parts: { string } = { "local allocate = ...\n" }
	local exports: { string } = {}
	local functions: { string } = {}

	for _, event: Event in events(file) do
		local write: Block = Blocks.new("write", event.name)
		local read: Block = Blocks.new("read", event.name)
		local names: { string }, values: { string } = {}, {}

		if event.data then
			names, values = emitter:block(event.data, write, read)
		end

		-- The fire takes each value typed as Luau sees it; a reader with nothing to read names no packet
		local typed: { string } = {}
		for index: number, field: Field in parameters(event) do
			typed[index] = `{names[index]}: {luauType(field.type)}`
		end

		local body: string = read:done()
		local arguments: string = body == "" and "_, cursor: number" or "packet: buffer, cursor: number, length: number"
		local results: string = #values == 0 and "" or `, {table.concat(values, ", ")}`

		table.insert(functions, `local function write{event.name}({table.concat(typed, ", ")})\n{write:done()}end\n`)
		table.insert(functions, `local function read{event.name}({arguments})\n{body}\treturn cursor{results}\nend\n`)
		table.insert(exports, `\t{event.name} = \{ write = write{event.name}, read = read{event.name} },`)
	end

	local helpers: { string } = {}
	for name: string in emitter.helpers do
		table.insert(helpers, name)
	end
	table.sort(helpers)

	for _, name: string in helpers do
		table.insert(parts, Emit.HELPERS[name])
	end

	table.move(functions, 1, #functions, #parts + 1, parts)
	table.insert(parts, `return \{\n{table.concat(exports, "\n")}\n}\n`)

	return table.concat(parts, "\n")
end

--[[
    Loads a rendered chunk with an allocator that grows a buffer as the
    writers ask, and a packet function that hands back exactly what was
    written since the last call
--]]

local function load(text: string): (any, () -> buffer)
	local out: buffer = buffer.create(64)
	local cursor: number = 0

	local function allocate(bytes: number): (number, buffer)
		if cursor + bytes > buffer.len(out) then
			local grown: buffer = buffer.create(math.max(buffer.len(out) * 2, cursor + bytes))
			buffer.copy(grown, 0, out, 0, cursor)
			out = grown
		end

		local offset: number = cursor
		cursor += bytes

		return offset, out
	end

	local function packet(): buffer
		local exact: buffer = buffer.create(cursor)
		buffer.copy(exact, 0, out, 0, cursor)
		cursor = 0
		return exact
	end

	return luau.load(text, { debugName = "Scalars" })(allocate), packet
end

-- The least and most a number of a type may be
local function bounds(node: any): (number, number)
	local reach: number = FLOAT_REACH[node.name] or 0
	local natural: { number } = Analyse.BOUNDS[node.name] or { -reach, reach }
	local range = node.range

	return range and range.min or natural[1], range and range.max or natural[2]
end

local function randomBytes(count: number): string
	local bytes: { string } = table.create(count)
	for index: number = 1, count do
		bytes[index] = string.char(math.random(0, 255))
	end
	return table.concat(bytes)
end

--[[
    A value of a type: its least or most when an end is asked for, or
    one at random within its bounds
--]]

local function valueOf(node: Type, ends: string?): any
	local shape: any = primitive(node)
	local name: string = shape.name

	if name == "boolean" then
		if ends then
			return ends == "max"
		end

		return math.random() < 0.5
	elseif name == "string" or name == "buffer" then
		local _, low: number, high: number = Analyse.prefix(shape.range)
		high = math.min(high, FREE_LENGTH)

		local count: number = ends == "min" and low or ends == "max" and high or math.random(low, high)
		local text: string = randomBytes(count)

		return name == "buffer" and buffer.fromstring(text) or text
	end

	local low: number, high: number = bounds(shape)

	if ends then
		return ends == "min" and low or high
	elseif Analyse.BOUNDS[name] then
		return low + math.floor(math.random() * (high - low))
	end

	return low + math.random() * (high - low)
end

--[[
    Whether a value read back matches the one written: exactly for most
    types, and within the precision the wire has for halves, singles
    and quantised floats
--]]

local function near(node: Type, expected: any, actual: any): boolean
	local shape: any = primitive(node)
	local name: string = shape.name

	if name == "f16" then
		return math.abs(expected - actual) <= math.abs(expected) / 1024 + 2 ^ -24
	elseif name == "f32" then
		return math.abs(expected - actual) <= math.abs(expected) / 2 ^ 23
	elseif LEVELS[name] then
		local low: number, high: number = bounds(shape)
		return math.abs(expected - actual) <= (high - low) / LEVELS[name] / 2 + 1e-9
	elseif name == "buffer" then
		return buffer.tostring(expected) == buffer.tostring(actual)
	end

	return expected == actual
end

describe("Emit", function ()
	local file: Parser.File = compile(fs.readFile(SCHEMA))
	local text: string = render(file)
	local byName: { [string]: Event } = {}

	for _, event: Event in events(file) do
		byName[event.name] = event
	end

	-- Every parameter of an event at its least, as a list the write takes
	local function least(name: string): { any }
		local written: { any } = {}
		for index: number, field: Field in parameters(byName[name]) do
			written[index] = valueOf(field.type, "min")
		end
		return written
	end

	local function failure(ok: boolean, message: any, expected: string)
		expect(ok).is(false)
		expect(tostring(message):find(expected, 1, true) ~= nil).is(true)
	end

	test("renders the scalar schema as the golden file", function ()
		if table.find(process.args, "--update") then
			if not fs.isDir(GOLDEN_DIRECTORY) then
				fs.writeDir(GOLDEN_DIRECTORY)
			end

			fs.writeFile(GOLDEN, text)
		end

		expect(fs.isFile(GOLDEN) and fs.readFile(GOLDEN) or "").is(text)
	end)

	describe("round trips", function ()
		local module: any, packet: () -> buffer = load(text)

		for _, event: Event in events(file) do
			test(event.name, function ()
				local fields: { Field } = parameters(event)

				for round: number = 0, ROUNDS do
					local ends: string? = round == 0 and "min" or round == 1 and "max" or nil
					local written: { any } = {}

					for index: number, field: Field in fields do
						written[index] = valueOf(field.type, ends)
					end

					module[event.name].write(table.unpack(written, 1, #fields))

					local bytes: buffer = packet()
					local read: { any } = { module[event.name].read(bytes, 0, buffer.len(bytes)) }

					expect(read[1]).is(buffer.len(bytes))

					for index: number, field: Field in fields do
						local message: string =
							`{event.name}.{field.name}: wrote {written[index]}, read {read[index + 1]}`
						assert(near(field.type, written[index], read[index + 1]), message)
					end
				end
			end)
		end
	end)

	describe("writers refuse", function ()
		local module: any = load(text)

		local REFUSALS: { { any } } = {
			{ "Integers", 1, 0.5, "Integers.a: expected u8" },
			{ "Integers", 2, 1000, "Integers.b: expected u16(1..999)" },
			{ "Integers", 6, 2 ^ 53 + 2, "Integers.f: expected u64" },
			{ "Floats", 1, 0 / 0, "Floats.a: expected f16" },
			{ "Floats", 3, 2, "Floats.c: expected f64(0..1)" },
			{ "Flags", 1, 1, "Flags.a: expected boolean" },
			{ "Bytes", 1, 5, "Bytes.name: expected string" },
			{ "Bytes", 1, string.rep("x", 33), "Bytes.name: length out of range" },
			{ "Bytes", 2, "abc", "Bytes.tag: expected 4 bytes" },
			{ "Bytes", 3, "raw", "Bytes.raw: expected buffer" },
		}

		for _, row: { any } in REFUSALS do
			test(row[4], function ()
				local written: { any } = least(row[1])
				written[row[2]] = row[3]

				local ok: boolean, message: any = pcall(module[row[1]].write, table.unpack(written, 1, #written))
				failure(ok, message, row[4])
			end)
		end
	end)

	describe("with write validation off", function ()
		local loose: string = render(compile(`option writeValidation = false\n{fs.readFile(SCHEMA)}`))
		local module: any = load(loose)

		test("no writer checks a value's type or range", function ()
			local written: { any } = least("Integers")
			written[1] = 0.5
			written[2] = 1000

			expect((loose:find("typeof", 1, true))).is(nil)
			expect((pcall(module.Integers.write, table.unpack(written, 1, #written)))).is(true)
		end)

		test("a length outside its bounds is still refused", function ()
			local written: { any } = least("Bytes")
			written[1] = string.rep("x", 33)

			local ok: boolean, message: any = pcall(module.Bytes.write, table.unpack(written, 1, #written))
			failure(ok, message, "Bytes.name: length out of range")
		end)
	end)

	describe("readers refuse", function ()
		local module: any, packet: () -> buffer = load(text)

		-- The packet of an event fired with every parameter at its least
		local function packetOf(name: string): buffer
			local written: { any } = least(name)
			module[name].write(table.unpack(written, 1, #parameters(byName[name])))
			return packet()
		end

		local function refused(name: string, bytes: buffer, length: number, expected: string)
			local ok: boolean, message: any = pcall(module[name].read, bytes, 0, length)
			failure(ok, message, expected)
		end

		test("a block past the packet's end", function ()
			refused("Value", buffer.create(1), 1, "Value: truncated")
		end)

		test("an integer outside its declared range", function ()
			local bytes: buffer = packetOf("Integers")
			buffer.writeu16(bytes, 1, 1000)
			refused("Integers", bytes, buffer.len(bytes), "Integers.b: out of range")
		end)

		test("a 64-bit integer past what a number holds exactly", function ()
			local bytes: buffer = packetOf("Integers")
			buffer.writeu32(bytes, 16, 1)
			buffer.writeu32(bytes, 20, 2 ^ 21)
			refused("Integers", bytes, buffer.len(bytes), "Integers.f: out of range")
		end)

		test("NaN on a float", function ()
			local bytes: buffer = packetOf("Floats")
			buffer.writef32(bytes, 2, 0 / 0)
			refused("Floats", bytes, buffer.len(bytes), "Floats.b: out of range")
		end)

		test("a float outside its declared range", function ()
			local bytes: buffer = packetOf("Floats")
			buffer.writef64(bytes, 6, 2)
			refused("Floats", bytes, buffer.len(bytes), "Floats.c: out of range")
		end)

		test("a length past its bound", function ()
			local bytes: buffer = packetOf("Bytes")
			buffer.writeu8(bytes, 0, 40)
			refused("Bytes", bytes, buffer.len(bytes), "Bytes.name: length out of range")
		end)

		test("a payload past the packet's end", function ()
			local bytes: buffer = packetOf("Bytes")
			refused("Bytes", bytes, buffer.len(bytes) - 1, "Bytes.name: truncated")
		end)
	end)
end)
