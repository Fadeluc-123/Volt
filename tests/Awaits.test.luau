--[[
    Proves the awaited compiler: AwaitedInstance refused anywhere but the
    data of a from: Server event that is not ordered, as a key and with a
    type argument, a timeout warned about where nothing waits, the print
    and the size; and the Awaited schema renders as its golden modules
--]]

--!strict
local fs = require("@lune/fs")

local Suite = require("./Suite")
local Generated = require("./Generated")
local golden = require("./Expected")
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

local AWAITED: string = fs.readFile("tests/Schemas/Awaited.volt")
local CLIENT: string, SERVER: string = Generated.modules("Awaited", AWAITED)
local MODEL: string = "AwaitedInstance(Model)"
local START: string = "\tlocal start: number, sideStart: number = cursor, sideCursor\n" -- An awaited reader's first line
local SERVER_DATA: string = "a from: Server event's data"

-- Each event of Awaited's World by its client id, whether its data reaches an AwaitedInstance, and whether through Tracked
local EVENTS: { { any } } = {
	{ "Spawned", 1, true, false },
	{ "Plain", 2, false, false },
	{ "Group", 3, true, false },
	{ "Brief", 4, true, false },
	{ "Track", 5, true, true },
}

-- An AwaitedInstance where it may not travel, where the refusal says it may and what reaches it, and the case
local REFUSED: { { string } } = {
	{
		`event E \{ from: Client, type: Reliable, call: Polling, data: {MODEL} }`,
		`{SERVER_DATA}; E is from: Client`,
		"a Client event's data",
	},
	{
		`event E \{ from: Both, type: Reliable, call: Polling, data: {MODEL} }`,
		`{SERVER_DATA}; E is from: Both`,
		"a Both event's data",
	},
	{ `function F \{ data: {MODEL} }`, `{SERVER_DATA}; F is a function`, "a function's data" },
	{ `function F \{ return: {MODEL} }`, `{SERVER_DATA}; F is a function`, "a function's return" },
	{ `export type T = {MODEL}`, `{SERVER_DATA}; T is exported`, "an exported type" },
	{
		`type T = struct \{ at: {MODEL} }\nevent E \{ from: Client, type: Reliable, call: Polling, data: T }`,
		`{SERVER_DATA}; E is from: Client`,
		"a Client event's data, through a named type",
	},
	{
		`event E \{ from: Server, type: OrderedUnreliable, call: Polling, data: {MODEL} }`,
		"a Reliable or Unreliable event's data; E is OrderedUnreliable",
		"an ordered event's data, whose replay would skip the sequence check",
	},
}

-- What resolving and analysing a fragment reports, warnings included
local function analysed(text: string): Diagnostics.Diagnostics
	local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(Source.new("Test.volt", text))
	local file: Schema.File = Parser.parse(Lexer.scan(diagnostics.source, diagnostics), diagnostics)

	Resolve.file(file, diagnostics)
	Analyse.file(file, diagnostics)

	return diagnostics
end

-- A generated function's text, from its first line to the end that closes it
local function body(text: string, name: string): string
	return text:match(`local function {name}%(.-\nend\n`) :: string
end

-- A schema table's row for a message, by its name
local function row(text: string, name: string): string
	return text:match(`\{ name = "{name}"[^\n]*`) :: string
end

-- Whether a text holds a piece of plain text
local function holds(text: string, piece: string): boolean
	return text:find(piece, 1, true) ~= nil
end

describe("Awaits", function ()
	describe("diagnostics", function ()
		for _, case: { string } in REFUSED do
			test(`V3022 refuses it in {case[3]}, at the AwaitedInstance`, function ()
				local text: string = `{HEADER}{case[1]}`
				local message: string = `error V3022: {MODEL} travels only in {case[2]}`

				expect(analysed(text):render()).is(rendered(text, MODEL, message))
			end)
		end

		test("V3008 refuses it as a map key or a set element", function ()
			local text: string = `{HEADER}type M = \{ [{MODEL}]: u8 }\ntype S = set<{MODEL}>`
			local arrived: string = "whose instance may not have arrived when it is read"
			local key: string = rendered(text, MODEL, `error V3008: a map key cannot be {MODEL}, {arrived}`)
			local element: string = rendered(text, MODEL, `error V3008: a set element cannot be {MODEL}, {arrived}`, 2)

			expect(analysed(text):render()).is(`{key}\n\n{element}`)
		end)

		test("V3007 refuses a type argument", function ()
			local text: string = `{HEADER}type T = AwaitedInstance<u8>`
			local message: string = "error V3007: AwaitedInstance takes no type arguments, got 1"

			expect(analysed(text):render()).is(rendered(text, "AwaitedInstance<u8>", message))
		end)

		test("V3006 warns about a timeout on an event whose data reaches none, and not on one whose does", function ()
			local event: string = "event E { from: Server, type: Reliable, call: Polling, timeout: 2"
			local text: string = `{HEADER}{event}, data: u8 }`
			local waiting: string = `{HEADER}{event}, data: {MODEL}? }`
			local message: string =
				"warning V3006: timeout on an event whose data reaches no AwaitedInstance has no effect; nothing waits"
			local diagnostics: Diagnostics.Diagnostics = analysed(text)

			expect(diagnostics:render()).is(rendered(text, "timeout", message))
			expect(diagnostics.errors).is(0)
			expect(analysed(waiting):render()).is("")
		end)

		test("V3005 refuses a timeout that is not positive", function ()
			local text: string =
				`{HEADER}event E \{ from: Server, type: Reliable, call: Polling, timeout: 0, data: {MODEL} }`
			local message: string = "error V3005: timeout must be a positive number, got 0"

			expect(analysed(text):render()).is(rendered(text, "timeout", message))
		end)

		test("V4002 keeps its name from a top-level type, which no reference could reach", function ()
			local ok: boolean, message: any = pcall(Generated.modules, "Test", `{HEADER}type AwaitedInstance = u8`)
			local expected: string =
				`error V4002: "AwaitedInstance" is a Roblox type the schema language names and cannot name a type`

			expect(ok).is(false)
			expect(holds(tostring(message), expected)).is(true)
		end)
	end)

	test("prints itself, QuaternionCFrame<f32> and a timeout, and an event that sets no timeout prints none", function ()
		local data: string = `data: (a: {MODEL}, b: QuaternionCFrame<f32>)`
		local plain: string = `event F \{ from: Server, type: Reliable, call: Polling, data: {MODEL}`
		local text: string =
			`{HEADER}event E \{ from: Server, type: Reliable, call: Polling, timeout: 2, {data} }\n{plain} }`
		local printed: string = Print.file((Generated.compile("Test", text)))

		expect(holds(printed, `call: Polling, {data}, queue: 64, rate: 120, timeout: 2 }`)).is(true)
		expect(holds(printed, `{plain}, queue: 64, rate: 120 }`)).is(true)
	end)

	test("takes four bytes and no slot", function ()
		local file: Schema.File = Generated.compile("Test", `{HEADER}type T = {MODEL}`)
		local size: Sizes.Size = Sizes.size((file.declarations[1] :: Schema.TypeDeclaration).type)

		expect(`{size.min} {size.max} {size.bits} {size.slots}`).is("4 4 0 0")
	end)

	describe("the Awaited schema", function ()
		for _, side in { { name = "Client", text = CLIENT }, { name = "Server", text = SERVER } } do
			test(`renders the {side.name:lower()} module as its golden file`, function ()
				expect(golden("tests/Golden/Awaited", side.name, side.text)).is(side.text)
			end)
		end

		for _, event: { any } in EVENTS do
			local name: string, id: number, awaited: boolean, paired: boolean = event[1], event[2], event[3], event[4]

			test(`World.{name} {awaited and "waits" or "does not wait"} for its instances on the client`, function ()
				local reader: string = body(CLIENT, `readWorld_{name}`)
				local opening: string = reader:match("^[^\n]*\n([^\n]*\n)") :: string
				local await: string = `return runtime:await({id}, packet, start, cursor, side, sideStart, sideCursor, `
				local deliver: string = `return runtime:deliver({id}, player, cursor, sideCursor, `

				expect(opening == START).is(awaited)
				expect(holds(reader, awaited and await or deliver)).is(true)
				expect(holds(row(CLIENT, `World.{name}`), "timeout = ")).is(awaited)

				-- A reader or writer that goes through Tracked looks its instance up in the shared pair instead
				expect(holds(reader, "instanceById(")).is(awaited and not paired)
				expect(holds(body(SERVER, `writeWorld_{name}`), "instanceId(")).is(awaited and not paired)
			end)
		end

		test(
			"carries each event's timeout, or the file's, and each instance local only on the side that calls it",
			function ()
				expect(holds(row(CLIENT, "World.Brief"), "timeout = 0.001,")).is(true)
				expect(holds(row(CLIENT, "World.Spawned"), "timeout = 10,")).is(true)
				expect(holds(body(CLIENT, "readTracked"), "instanceById(")).is(true)
				expect(holds(body(SERVER, "writeTracked"), "instanceId(")).is(true)
				expect(`{holds(CLIENT, "local instanceById:")} {holds(CLIENT, "instanceId")}`).is("true false")
				expect(`{holds(SERVER, "local instanceId:")} {holds(SERVER, "instanceById")}`).is("true false")
			end
		)
	end)

	test("an event on a channel waits as one on the default stream does", function ()
		local text: string =
			`{HEADER}channel Bulk\nevent E \{ from: Server, type: Reliable, call: Polling, channel: Bulk, data: {MODEL} }`
		local client: string = Generated.modules("Test", text)
		local reader: string = body(client, "readE")

		expect(holds(reader, START)).is(true)
		expect(holds(reader, "return runtime:await(1, packet, start, cursor, side, sideStart, sideCursor, ")).is(true)
		expect(holds(row(client, "E"), "timeout = 10,")).is(true)
	end)
end)
