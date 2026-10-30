--[[
    Proves every declaration form parses into the node the design describes
    by printing it back to source, that attributes land in their set and
    are refused at the attribute, that recovery keeps the next attribute or
    channel, that a channel is read only where a name follows the word, and
    that a function the server calls is read and checked as its own
--]]

--!strict
local Suite = require("./Suite")
local rendered = require("./Rendered")
local Analyse = require("@volt/Compiler/Analyse")
local Diagnostics = require("@volt/Compiler/Diagnostics")
local Lexer = require("@volt/Compiler/Lexer")
local Parser = require("@volt/Compiler/Parser")
local Print = require("@volt/Compiler/Analyse/Print")
local Resolve = require("@volt/Compiler/Resolve")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Source = require("@volt/Compiler/Source")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Declaration = Schema.Declaration
type Set = Schema.Attributes

-- The two options every schema must carry, so a fragment compiles clean
local HEADER: string = `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"\n`

-- Every declaration form, as written and as it prints back when the two differ
local DECLARATIONS: { { string } } = {
	{ "type Reference = string(1..64)" },
	{ "export type Reference = string(1..64)" },
	{
		"struct Stack { item: string(1..32), quantity: u16(1..999), properties: unknown? }",
		"type Stack = struct { item: string(1..32), quantity: u16(1..999), properties: unknown? }",
	},
	{
		"export struct Save { version: u16, stacks: Stack[0..256], }",
		"export type Save = struct { version: u16, stacks: Stack[0..256] }",
	},
	{ "enum Team { Red, Blue }", "type Team = enum { Red, Blue }" },
	{
		`export enum Shape "kind" \{ Circle \{ radius: f32 }, Point }`,
		`export type Shape = enum "kind" \{ Circle \{ radius: f32 }, Point }`,
	},
	{
		"event Input { from: Client, type: Unreliable, call: SingleSync, data: (dir: u8(0..8), jump: boolean), queue: 8, rate: unlimited }",
	},
	{ "event Damage { from: Server, type: Reliable, call: ManyAsync, data: struct { targetId: u16, amount: u16 } }" },
	{ "event Tick { from: Both, type: Reliable, call: Polling, data: () }" },
	{
		"function GetInventory { data: (reference: Reference), return: (ok: boolean, stacks: Stack[0..256]), yield: Promise, timeout: 5, rate: 60 }",
	},
	{ "function Ping {}" },
	{ "function Confirm { from: Server, data: (title: string(1..64), seconds: u8), return: boolean, timeout: 2 }" },
	{
		"namespace Combat { event Hit { from: Client, type: Reliable, call: SingleSync } namespace Inner { type Id = u8 } }",
		"namespace Combat {\n\tevent Hit { from: Client, type: Reliable, call: SingleSync }\n\tnamespace Inner {\n\t\ttype Id = u8\n\t}\n}",
	},
	{ "@private type Cursor = u16(0..4096)" },
	{ "@private struct Page { first: u16 }", "@private type Page = struct { first: u16 }" },
	{ "namespace Ui { @private enum Mode { On } }", "namespace Ui {\n\t@private type Mode = enum { On }\n}" },
	{ "channel Bulk" },
	{ "namespace Net { channel Fast }", "namespace Net {\n\tchannel Fast\n}" },
	{ "event Chat { from: Both, type: Reliable, call: ManySync, data: string(0..200), channel: Bulk }" },
	{ "event Aim { from: Client, type: OrderedUnreliable, call: SingleSync, data: (yaw: q16(-3.2..3.2)) }" },
	{ "@delta event vitals { from: Server, type: Reliable, call: SingleAsync, data: Vitals }" },
	{ "@dictionary @private type Item = string(1..32)", "@private @dictionary type Item = string(1..32)" },
}

--[[
    Lexes and parses a fragment, returning the file and its diagnostics
--]]

local function parse(text: string): (Schema.File, Diagnostics.Diagnostics)
	local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(Source.new("Test.volt", text))
	local file: Schema.File = Parser.parse(Lexer.scan(diagnostics.source, diagnostics), diagnostics)

	return file, diagnostics
end

local function report(text: string): string
	local diagnostics = select(2, parse(text))
	return diagnostics:render()
end

-- What resolving and analysing a schema text reports, warnings included
local function analysed(text: string): Diagnostics.Diagnostics
	local file: Schema.File, diagnostics = parse(text)

	Resolve.file(file, diagnostics)
	Analyse.file(file, diagnostics)
	return diagnostics
end

-- The attributes a parsed declaration carries, as the schema node holds them
local function attributesOf(declaration: Declaration): Set?
	return (declaration.kind == "type" or declaration.kind == "event") and declaration.attributes or nil
end

describe("Declarations", function ()
	for _, pair: { string } in DECLARATIONS do
		test(pair[1], function ()
			local file: Schema.File, diagnostics = parse(pair[1])

			expect(diagnostics:render()).is("")
			expect(#file.declarations).is(1)
			expect(Print.file({ options = { spans = {} }, declarations = file.declarations })).is(pair[2] or pair[1])
		end)
	end

	test("@private lands in the set of a type, a struct and an enum, on its line or the one above", function ()
		local text: string =
			"@private type Cursor = u16\n@private\nstruct Page { first: Cursor }\nnamespace Ui {\n\t@private\n\tenum Mode { On }\n}\ntype Plain = u8"
		local file: Schema.File, diagnostics = parse(text)
		local namespace: Schema.Namespace = file.declarations[3] :: Schema.Namespace

		expect(diagnostics:render()).is("")
		expect((attributesOf(file.declarations[1]) :: Set).private).is(true)
		expect((attributesOf(file.declarations[2]) :: Set).private).is(true)
		expect((attributesOf(namespace.declarations[1]) :: Set).private).is(true)
		expect(attributesOf(file.declarations[4])).is(nil)
	end)

	test("@delta lands in the set of an event and @dictionary in the set of a type", function ()
		local text: string =
			"@delta event vitals { from: Server, type: Reliable, call: SingleAsync }\n@dictionary\ntype Item = string(1..32)\nevent Plain { from: Server, type: Reliable, call: Polling }"
		local file: Schema.File, diagnostics = parse(text)

		expect(diagnostics:render()).is("")
		expect((attributesOf(file.declarations[1]) :: Set).delta).is(true)
		expect((attributesOf(file.declarations[2]) :: Set).dictionary).is(true)
		expect(attributesOf(file.declarations[3])).is(nil)
	end)

	describe("diagnostics", function ()
		test("V2002 reports an attribute written twice and keeps the first", function ()
			local text: string = "@private @private type Cursor = u16"
			local file: Schema.File = parse(text)

			expect(report(text)).is(rendered(text, "@private", `error V2002: duplicate attribute "@private"`, 2))
			expect((attributesOf(file.declarations[1]) :: Set).private).is(true)
		end)

		test("V2011 reports an attribute that is no row, naming those that are", function ()
			local text: string = "@stable type Cursor = u16"
			local file: Schema.File = parse(text)
			local message: string =
				`error V2011: unknown attribute "@stable"; attributes are @private, @delta, @dictionary, @depth`

			expect(report(text)).is(rendered(text, "@stable", message))
			expect(#file.declarations).is(1)
			expect(attributesOf(file.declarations[1])).is(nil)
		end)

		test("V2012 reports @private on an option, an event, a function, a namespace and an exported type", function ()
			local fragment: { string } = {
				"@private option flush = 2",
				"@private event Input { from: Client, type: Reliable, call: Polling }",
				"@private function Ask {}",
				"@private namespace Combat {}",
				"@private export type Save = u16",
			}
			local text: string = table.concat(fragment, "\n")
			local file: Schema.File = parse(text)
			local applies: string = `error V2012: "@private" applies to a type, struct or enum, not to`
			local expected: { string } = {
				rendered(text, "@private", `{applies} option flush`),
				rendered(text, "@private", `{applies} event Input`, 2),
				rendered(text, "@private", `{applies} function Ask`, 3),
				rendered(text, "@private", `{applies} namespace Combat`, 4),
				rendered(text, "@private", "error V2012: an exported type cannot be @private", 5),
			}

			expect(report(text)).is(table.concat(expected, "\n\n"))
			expect(file.options.flush).is(2)
			expect(#file.declarations).is(4)
			expect(attributesOf(file.declarations[4])).is(nil)
		end)

		test("V2012 reports @delta on a type, and @dictionary on an event and on an exported type", function ()
			local fragment: { string } = {
				"@delta type Cursor = u16",
				"@dictionary event Input { from: Server, type: Reliable, call: Polling }",
				"@dictionary export type Name = string(1..8)",
			}
			local text: string = table.concat(fragment, "\n")
			local file: Schema.File = parse(text)
			local expected: { string } = {
				rendered(text, "@delta", `error V2012: "@delta" applies to an event, not to type Cursor`),
				rendered(
					text,
					"@dictionary",
					`error V2012: "@dictionary" applies to a type, struct or enum, not to event Input`
				),
				rendered(text, "@dictionary", "error V2012: an exported type cannot be @dictionary", 2),
			}

			expect(report(text)).is(table.concat(expected, "\n\n"))
			expect(#file.declarations).is(3)

			for _, declaration: Declaration in file.declarations do
				expect(attributesOf(declaration)).is(nil)
			end
		end)
	end)

	describe("a function the server calls", function ()
		test("from: Server lands on the function, and one without from has none", function ()
			local file: Schema.File, diagnostics = parse("function Confirm { from: Server }\nfunction Ping {}")
			local confirm: Schema.Function = file.declarations[1] :: Schema.Function
			local ping: Schema.Function = file.declarations[2] :: Schema.Function

			expect(diagnostics:render()).is("")
			expect(confirm.from).is("Server")
			expect(ping.from).is(nil)
		end)

		test("V2005 refuses from: Both, since a function names one caller", function ()
			local text: string = "function Tell { from: Both }"
			local message: string = `error V2005: expected one of Client, Server for key "from", got "Both"`

			expect(report(text)).is(rendered(text, "Both", message))
		end)

		test("V3006 warns about a rate on a from: Server function", function ()
			local text: string = `{HEADER}function Tell \{ from: Server, rate: 5 }`
			local message: string =
				"warning V3006: rate on a from: Server function has no effect; the server limits no reply it reads"
			local diagnostics: Diagnostics.Diagnostics = analysed(text)

			expect(diagnostics:render()).is(rendered(text, "rate", message))
			expect(diagnostics.errors).is(0)
		end)

		-- A refusal's reason alone takes a reply to 262 bytes, so the cap sits between that and the long return's
		test(
			"V3012 refuses a reply the client cannot send beside the handshake, and the call it answers is not held",
			function ()
				local fragment: { string } = {
					"option maxPacket = 300",
					"function Fits { from: Server, data: string(0..300) }",
					"function Big { from: Server, return: string(0..300) }",
				}
				local text: string = `{HEADER}{table.concat(fragment, "\n")}`
				local message: string =
					"error V3012: function Big's reply can reach 306 bytes, over maxPacket 300 with the 5-byte handshake"

				expect(analysed(text):render()).is(rendered(text, "Big", message))
			end
		)
	end)

	describe("a channel", function ()
		test("is a declaration only where the name channel is followed by a name", function ()
			local text: string =
				"type channel = u8\nstruct Load { channel: channel }\ntype Alias = channel\nchannel Bulk"
			local file: Schema.File, diagnostics = parse(text)
			local kinds: { string } = {}

			for _, declaration: Declaration in file.declarations do
				table.insert(kinds, `{declaration.kind} {declaration.name}`)
			end

			expect(diagnostics:render()).is("")
			expect(table.concat(kinds, ", ")).is("type channel, type Load, type Alias, channel Bulk")
		end)

		test("a parameter may be named channel, beside the event's channel key", function ()
			local text: string =
				"event Pick { from: Client, type: Reliable, call: Polling, data: (channel: u8), channel: Bulk }"
			local file: Schema.File, diagnostics = parse(text)
			local event: Schema.Event = file.declarations[1] :: Schema.Event

			expect(diagnostics:render()).is("")
			expect(event.channel).is("Bulk")
			expect((event.data :: Schema.Pack).parameters[1].name).is("channel")
		end)

		test("V2003 refuses a channel on a function, whose call and reply ride the default stream", function ()
			local text: string = "function Ask { channel: Bulk }"
			local message: string =
				`error V2003: unknown key "channel" in function Ask; keys are from, data, return, yield, timeout, rate`

			expect(report(text)).is(rendered(text, "channel", message))
		end)

		test("V2012 refuses @private on a channel", function ()
			local text: string = "@private channel Bulk"
			local message: string = `error V2012: "@private" applies to a type, struct or enum, not to channel Bulk`

			expect(report(text)).is(rendered(text, "@private", message))
		end)

		test("recovery after a broken declaration stops at a channel", function ()
			local file: Schema.File, diagnostics = parse("struct Broken { x: }\nchannel Bulk")

			expect(diagnostics.errors).is(1)
			expect(#file.declarations).is(1)
			expect(file.declarations[1].kind).is("channel")
		end)
	end)

	test("option stamp is read as true or false", function ()
		local file: Schema.File, diagnostics = parse("option stamp = true")
		local text: string = "option stamp = 1"
		local message: string = `error V2005: expected true or false for key "stamp", got "1"`

		expect(diagnostics:render()).is("")
		expect(file.options.stamp).is(true)
		expect(report(text)).is(rendered(text, "1", message))
	end)

	test("a declaration after a broken one keeps its attribute, since recovery stops at an @ and a name", function ()
		local text: string = "struct Broken { x: }\n@private struct Kept { y: u8 }"
		local file: Schema.File, diagnostics = parse(text)

		expect(diagnostics.errors).is(1)
		expect(#file.declarations).is(1)
		expect(file.declarations[1].name).is("Kept")
		expect((attributesOf(file.declarations[1]) :: Set).private).is(true)
	end)
end)
