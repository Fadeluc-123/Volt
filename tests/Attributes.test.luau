--[[
    Proves the replication attributes in the compiler: a @delta event and
    a @dictionary type refused where they break their rules, a dictionary
    string sized as its id and never shared, a @delta payload sized as its
    mask and its fields, the print and the hash, and both fixtures clean
--]]

--!strict
local fs = require("@lune/fs")

local Suite = require("./Suite")
local Generated = require("./Generated")
local rendered = require("./Rendered")
local Analyse = require("@volt/Compiler/Analyse")
local Diagnostics = require("@volt/Compiler/Diagnostics")
local Lexer = require("@volt/Compiler/Lexer")
local Parser = require("@volt/Compiler/Parser")
local Print = require("@volt/Compiler/Analyse/Print")
local Resolve = require("@volt/Compiler/Resolve")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Sizes = require("@volt/Compiler/Analyse/Sizes")
local Source = require("@volt/Compiler/Source")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

-- The two options every schema must carry, so a fragment compiles clean
local HEADER: string = `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"\n`

local DELTAS: string = fs.readFile("tests/Schemas/Deltas.volt")
local DICTIONARY: string = fs.readFile("tests/Schemas/Dictionary.volt")

local SERVER: string = "from: Server, type: Reliable, call: Polling" -- The one kind of event a @delta may mark

-- A struct reaching a @dictionary type, Item's second mention being the reference a refusal points at
local HELD: string = "@dictionary type Item = string(1..32)\nstruct Held { item: Item }\n"
local STREAM: string = "error V3017: @dictionary type Item travels only on the server's default reliable stream"

-- One field past what a mask holds, none named like a primitive
local FIELDS: { string } = {}
for index: number = 1, 33 do
	table.insert(FIELDS, `x{index}: u8`)
end

local BIG: string = `struct Big \{ {table.concat(FIELDS, ", ")} }\n`

-- A @delta a schema refuses, what the refusal points at, its message and which mention of that it is
local REFUSED: { { any } } = {
	{
		"@delta event a { from: Client, type: Reliable, call: Polling, data: struct { x: u8 } }",
		"from",
		"@delta event a must be from: Server; it is from: Client",
	},
	{
		"@delta event a { from: Server, type: Unreliable, call: Polling, data: struct { x: u8 } }",
		"type",
		"@delta event a must be Reliable; it is Unreliable",
	},
	{
		`@delta event a \{ {SERVER}, data: (x: u8) }`,
		"(x: u8)",
		"@delta event a must carry one struct; it carries a parameter pack",
	},
	{ `@delta event a \{ {SERVER}, data: u8 }`, "u8", "@delta event a must carry one struct; it carries u8" },
	{
		`{BIG}@delta event a \{ {SERVER}, data: Big }`,
		"Big",
		"@delta event a's struct must have 1 to 32 fields; it has 33",
		2,
	},
	{
		`@delta event a \{ {SERVER}, data: struct \{ m: StreamedInstance(Model), x: u8 } }`,
		"StreamedInstance(Model)",
		"@delta event a cannot carry StreamedInstance(Model), which a client can read as nil",
	},
	{
		`@delta event a \{ {SERVER}, data: struct \{ u: unknown? } }`,
		"unknown",
		"@delta event a cannot carry unknown, which a client can read as nil",
	},
	{
		`@delta event a \{ {SERVER}, data: struct \{ m: AwaitedInstance(Model) } }`,
		"AwaitedInstance(Model)",
		"@delta event a cannot carry AwaitedInstance(Model), which a client can wait for",
	},
}

-- A type @dictionary refuses, which is also what the refusal points at
local LONG: { string } = { "u16", "string", "string(1..300)" }

-- What reaches Item where its id may not travel, and why
local REACHED: { { string } } = {
	{ "event Use { from: Client, type: Reliable, call: Polling, data: Held }", "Use is from: Client" },
	{ "function Ask { data: Held }", "Ask is a function" },
	{ "event Tick { from: Server, type: Unreliable, call: Polling, data: Held }", "Tick is Unreliable" },
	{ "export struct Save { held: Held }", "Save is exported" },
	{
		"channel Bulk\nevent Chat { from: Server, type: Reliable, call: Polling, channel: Bulk, data: Held }",
		"Chat rides channel Bulk",
	},
	{ "function Confirm { from: Server, return: Held }", "Confirm's return is the client's reply" },
}

-- Runs a text through every stage before the generator, returning the file, its diagnostics and the hash
local function compile(text: string): (Schema.File, Diagnostics.Diagnostics, number)
	local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(Source.new("Test.volt", text))
	local file: Schema.File = Parser.parse(Lexer.scan(diagnostics.source, diagnostics), diagnostics)

	Resolve.file(file, diagnostics)
	return file, diagnostics, Analyse.file(file, diagnostics)
end

local function report(text: string): string
	local diagnostics: Diagnostics.Diagnostics = select(2, compile(text))
	return diagnostics:render()
end

describe("Attributes", function ()
	describe("diagnostics", function ()
		for _, case: { any } in REFUSED do
			test(`V3015: {case[3]}`, function ()
				local text: string = `{HEADER}{case[1]}`

				expect(report(text)).is(rendered(text, case[2], `error V3015: {case[3]}`, case[4]))
			end)
		end

		for _, long: string in LONG do
			test(`V3016 refuses @dictionary on {long}, at the type`, function ()
				local text: string = `{HEADER}@dictionary type A = {long}`
				local message: string =
					`error V3016: @dictionary type A must be a string of at most 255 bytes, got {long}`

				expect(report(text)).is(rendered(text, long, message))
			end)
		end

		for _, case: { string } in REACHED do
			test(`V3017 refuses a @dictionary type where {case[2]}, at the reference`, function ()
				local text: string = `{HEADER}{HELD}{case[1]}`

				expect(report(text)).is(rendered(text, "Item", `{STREAM}; {case[2]}`, 2))
			end)
		end
	end)

	test("both fixtures compile clean", function ()
		expect(select(3, Generated.compile("Deltas", DELTAS)):render()).is("")
		expect(select(3, Generated.compile("Dictionary", DICTIONARY)):render()).is("")
	end)

	test("a @dictionary reference is its 2-byte id and never a shared pair, however often it is named", function ()
		local file: Schema.File = Generated.compile("Dictionary", DICTIONARY)
		local item: Schema.TypeDeclaration = file.declarations[1] :: Schema.TypeDeclaration
		local picked: Schema.Event = file.declarations[4] :: Schema.Event
		local reference: Sizes.Size = Sizes.size((picked.data :: Schema.Pack).parameters[1].type)
		local pack: Sizes.Size = Sizes.size(picked.data :: Schema.Pack)

		expect(item.references).is(3)
		expect(Sizes.shared(item)).is(false)
		expect(`{reference.min} {reference.max} {reference.bits} {reference.slots}`).is("2 2 0 0")
		expect(`{pack.min} {pack.max} {pack.bits} {pack.slots}`).is("4 4 0 0")
	end)

	test("a @delta payload takes a mask bit per field, each field a block only its bit sends", function ()
		local file: Schema.File = Generated.compile("Deltas", DELTAS)
		local vitals: Sizes.Size = Sizes.delta((file.declarations[2] :: Schema.Event).data :: Schema.Type)
		local zone: Sizes.Size = Sizes.delta((file.declarations[3] :: Schema.Event).data :: Schema.Type)

		expect(`{vitals.min} {vitals.max} {vitals.bits} {vitals.slots}`).is("0 23 5 0")
		expect(`{zone.min} {zone.max} {zone.bits} {zone.slots}`).is("0 3 2 0")
	end)

	test("prints an event's attributes before it and sizes a @delta payload by its mask", function ()
		local printed: string = Print.file((Generated.compile("Deltas", DELTAS)))
		local delta: string =
			"\n@delta event vitals { from: Server, type: Reliable, call: SingleAsync, data: Vitals, queue: 64, rate: 120 } -- to client 1, payload 1..24 bytes\n"
		local dictionary: string = "\n@dictionary type Item = string(1..32) -- "

		expect(printed:find(delta, 1, true) ~= nil).is(true)
		expect(Print.file((Generated.compile("Dictionary", DICTIONARY))):find(dictionary, 1, true) ~= nil).is(true)
	end)

	test("changes the hash when an event is marked @delta", function ()
		local plain: number = select(3, compile(`{HEADER}event a \{ {SERVER}, data: struct \{ x: u8 } }`))
		local marked: number = select(3, compile(`{HEADER}@delta event a \{ {SERVER}, data: struct \{ x: u8 } }`))

		expect(marked).never_is(plain)
	end)
end)
