--[[
    Proves resolution gives every declaration its path, binds every
    reference through the namespace rules, fills the option and message
    defaults, and reports each V300x diagnostic where it happens
--]]

--!strict
local Suite = require("./Suite")
local rendered = require("./Rendered")
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

-- The two options every schema must carry, so a fragment resolves clean
local HEADER: string = `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"\n`

local function schema(fragment: string): string
	return `{HEADER}{fragment}`
end

--[[
    Lexes, parses and resolves a text, returning the file and its diagnostics
--]]

local function resolve(text: string): (Schema.File, Diagnostics.Diagnostics)
	local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(Source.new("Test.volt", text))
	local file: Schema.File = Parser.parse(Lexer.scan(diagnostics.source, diagnostics), diagnostics)

	Resolve.file(file, diagnostics)
	return file, diagnostics
end

local function report(text: string): string
	local diagnostics: Diagnostics.Diagnostics = select(2, resolve(text))
	return diagnostics:render()
end

describe("Resolve", function ()
	test("fills every option default and takes the scope from the file name", function ()
		local file: Schema.File, diagnostics = resolve(schema("option queue = 8"))
		local options: any = file.options

		expect(diagnostics:render()).is("")
		expect(options.runtime).is("ReplicatedStorage.Packages.Volt")
		expect(options.scope).is("Test")
		expect(options.casing).is("camel")
		expect(options.writeValidation).is(true)
		expect(options.manualReplication).is(false)
		expect(options.flush).is(1)
		expect(options.maxPacket).is(8192)
		expect(options.maxPacketsPerSecond).is(240)
		expect(options.maxOutgoing).is(262144)
		expect(options.unreliableBudget).is(900)
		expect(options.queue).is(8)
		expect(options.rate).is(120)
		expect(options.functionRate).is(60)
		expect(options.timeout).is(10)
		expect(options.yield).is("coroutine")
		expect(options.typesOutput).is(nil)
		expect(options.promise).is(nil)
	end)

	test("fills message defaults from the options and keeps the keys a message sets", function ()
		local text: string = schema(
			`option queue = 8\noption rate = unlimited\noption functionRate = 30\noption timeout = 2\noption yield = promise\noption promise = "P"\nevent E \{ from: Client, type: Reliable, call: Polling }\nfunction F \{}\nfunction G \{ yield: Coroutine, timeout: 1, rate: 5 }`
		)
		local file: Schema.File, diagnostics = resolve(text)
		local event: any, first: any, second: any = file.declarations[1], file.declarations[2], file.declarations[3]

		expect(diagnostics:render()).is("")
		expect(event.queue).is(8)
		expect(event.rate).is("unlimited")
		expect(first.timeout).is(2)
		expect(first.rate).is(30)
		expect(first.yield).is("Promise")
		expect(second.timeout).is(1)
		expect(second.rate).is(5)
		expect(second.yield).is("Coroutine")
	end)

	test("gives every declaration its path and binds references through the namespace rules", function ()
		local text: string = schema(
			"type Id = u8\nnamespace A {\n\ttype Local = u8\n\tnamespace B {\n\t\ttype Deep = struct { a: Local, b: Id }\n\t\tevent E { from: Client, type: Reliable, call: Polling, data: A.Local }\n\t}\n\ttype Mine = B.Deep\n}\ntype Outer = A.B.Deep"
		)
		local file: Schema.File, diagnostics = resolve(text)
		local id: any, a: any, outer: any = file.declarations[1], file.declarations[2], file.declarations[3]
		local localType: any, b: any, mine: any = a.declarations[1], a.declarations[2], a.declarations[3]
		local deep: any, event: any = b.declarations[1], b.declarations[2]

		expect(diagnostics:render()).is("")
		expect(id.path).is("Id")
		expect(a.path).is("A")
		expect(localType.path).is("A.Local")
		expect(b.path).is("A.B")
		expect(deep.path).is("A.B.Deep")
		expect(event.path).is("A.B.E")
		expect(mine.path).is("A.Mine")
		expect(outer.path).is("Outer")
		expect(deep.type.fields[1].type.target).is(localType)
		expect(deep.type.fields[2].type.target).is(id)
		expect(event.data.target).is(localType)
		expect(mine.type.target).is(deep)
		expect(outer.type.target).is(deep)
		expect(id.references).is(1)
		expect(localType.references).is(2)
		expect(deep.references).is(2)
		expect(mine.references).is(0)
	end)

	test("binds an event's channel from its namespace outward to the channel's full path", function ()
		local text: string = schema(
			"channel Bulk\nnamespace Net {\n\tchannel Fast\n\tevent A { from: Client, type: Reliable, call: Polling, channel: Fast }\n\tevent B { from: Server, type: Reliable, call: Polling, channel: Bulk }\n}\nevent C { from: Both, type: Reliable, call: Polling }"
		)
		local file: Schema.File, diagnostics = resolve(text)
		local net: any, c: any = file.declarations[2], file.declarations[3]
		local fast: any, a: any, b: any = table.unpack(net.declarations)

		expect(diagnostics:render()).is("")
		expect(fast.path).is("Net.Fast")
		expect(a.channel).is("Net.Fast")
		expect(b.channel).is("Bulk")
		expect(c.channel).is(nil)
	end)

	test("a stamp set false is no stamp, so the schema prints and hashes as one without it", function ()
		local off: Schema.File = resolve(schema("option stamp = false"))
		local on: Schema.File = resolve(schema("option stamp = true"))

		expect(off.options.stamp).is(nil)
		expect(on.options.stamp).is(true)
	end)

	test("flushBytes prints after flush when a schema sets it, and not otherwise", function ()
		local set: Schema.File = resolve(schema("option flush = 4\noption flushBytes = 8"))
		local unset: Schema.File = resolve(schema("option flush = 4"))

		expect(Print.file(set):find("option flush = 4\noption flushBytes = 8\n", 1, true) ~= nil).is(true)
		expect(Print.file(unset):find("flushBytes", 1, true)).is(nil)
	end)

	describe("diagnostics", function ()
		test("V3001 reports an unknown name and a name that is not a type", function ()
			local text: string = schema(
				"type A = Missing\nevent E { from: Client, type: Reliable, call: Polling }\ntype B = E\nnamespace N { type C = u8 }\ntype D = C"
			)
			local first: string = rendered(text, "Missing", `error V3001: unknown type "Missing"`)
			local second: string = rendered(text, "E", `error V3001: "E" is an event, not a type`, 2)
			local third: string = rendered(text, "C", `error V3001: unknown type "C"`, 4)

			expect(report(text)).is(`{first}\n\n{second}\n\n{third}`)
		end)

		test("V3002 reports a second declaration of a path and keeps the first", function ()
			local text: string = schema(
				"type Dup = u8\ntype Dup = u16\nnamespace N { type Dup = u8 event Dup { from: Client, type: Reliable, call: Polling } }\ntype X = Dup"
			)
			local file: Schema.File = resolve(text)
			local first: string = rendered(text, "Dup", `error V3002: "Dup" is declared twice`, 2)
			local second: string = rendered(text, "Dup", `error V3002: "N.Dup" is declared twice`, 4)

			expect(report(text)).is(`{first}\n\n{second}`)
			expect((file.declarations[1] :: Schema.TypeDeclaration).references).is(1)
		end)

		test("V3003 reports a recursive type no value of which ends, at its name, once Expand has run", function ()
			local text: string = schema("struct Chain { next: Chain }\ntype Ends = struct { next: Ends? }")
			local message: string =
				`error V3003: "Chain" has no finite value: every way through it leads back to it; an optional, a collection that may be empty or another variant on the way ends it`

			expect(report(text)).is(rendered(text, "Chain", message))
		end)

		test(
			"V3004 reports the output options at the top of the file and promise where the yield asks for it",
			function ()
				local text: string = "type A = u8"
				local first: string = rendered(text, "t", "error V3004: missing option clientOutput")
				local second: string = rendered(text, "t", "error V3004: missing option serverOutput")
				local message: string = "error V3004: missing option promise; a promise yield needs the library's path"

				expect(report(text)).is(`{first}\n\n{second}`)
				expect(report(schema("option yield = promise"))).is(
					rendered(schema("option yield = promise"), "yield", message)
				)
				expect(report(schema("function F { yield: Promise }"))).is(
					rendered(schema("function F { yield: Promise }"), "yield", message)
				)
			end
		)

		test("V3004 reports at the top of the options file of a schema, which names its scope", function ()
			local source: Source.Source = Source.new("Types.volt", "type Id = u8\n")
			source:add("Game.volt", `option serverOutput = "Server.luau"\n`)

			local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(source)
			local file: Schema.File = Parser.schema(source, diagnostics)
			local location: string = "Game.volt:1:1: error V3004: missing option clientOutput"
			local excerpt: string = `    1 | option serverOutput = "Server.luau"`

			Resolve.file(file, diagnostics)

			expect(diagnostics:render()).is(`{location}\n{excerpt}\n      | ^`)
			expect(file.options.scope).is("Game")
		end)

		test("V3005 reports a number that is not positive, or not whole where it must be", function ()
			local text: string = schema(
				"option flush = 0\noption timeout = 0.5\noption queue = 1.5\nevent E { from: Client, type: Reliable, call: Polling, rate: -1 }\nfunction F { timeout: 0 }"
			)
			local first: string = rendered(text, "flush", "error V3005: flush must be a positive integer, got 0")
			local second: string = rendered(text, "queue", "error V3005: queue must be a positive integer, got 1.5")
			local third: string = rendered(text, "rate", "error V3005: rate must be a positive integer, got -1")
			local fourth: string = rendered(text, "timeout", "error V3005: timeout must be a positive number, got 0", 2)

			expect(report(text)).is(`{first}\n\n{second}\n\n{third}\n\n{fourth}`)
		end)

		test("V3001 reports an unknown channel, a name that is no channel and a channel where a type goes", function ()
			local text: string = schema(
				"channel Bulk\nevent Chat { from: Client, type: Reliable, call: Polling, channel: Bluk }\nevent Ping { from: Client, type: Reliable, call: Polling, channel: Chat }\ntype T = Bulk"
			)
			local expected: { string } = {
				rendered(text, "channel", `error V3001: unknown channel "Bluk"`, 2),
				rendered(text, "channel", `error V3001: "Chat" is an event, not a channel`, 3),
				rendered(text, "Bulk", `error V3001: "Bulk" is a channel, not a type`, 2),
			}

			expect(report(text)).is(table.concat(expected, "\n\n"))
		end)

		test("V3002 reports a channel and an event of one name, which share the name space", function ()
			local text: string = schema("channel Chat\nevent Chat { from: Client, type: Reliable, call: Polling }")

			expect(report(text)).is(rendered(text, "Chat", `error V3002: "Chat" is declared twice`, 2))
		end)

		test("V3014 refuses a channel on an Unreliable and an OrderedUnreliable event, at the key", function ()
			local text: string = schema(
				"channel Bulk\nevent Spray { from: Server, type: Unreliable, call: Polling, channel: Bulk }\nevent Aim { from: Client, type: OrderedUnreliable, call: Polling, channel: Bulk }"
			)
			local carries: string = "a channel carries Reliable events only"
			local expected: { string } = {
				rendered(text, "channel", `error V3014: event Spray is Unreliable; {carries}`, 2),
				rendered(text, "channel", `error V3014: event Aim is OrderedUnreliable; {carries}`, 3),
			}

			expect(report(text)).is(table.concat(expected, "\n\n"))
		end)

		test("V3005 reports a flushBytes of zero", function ()
			local text: string = schema("option flush = 4\noption flushBytes = 0")
			local message: string = "error V3005: flushBytes must be a positive integer, got 0"

			expect(report(text)).is(rendered(text, "flushBytes", message))
		end)

		test("V3013 warns about flushBytes when every frame flushes, and about nothing when some do not", function ()
			local text: string = schema("option flushBytes = 8")
			local message: string = "warning V3013: flushBytes means nothing when every frame flushes"
			local diagnostics: Diagnostics.Diagnostics = select(2, resolve(text))

			expect(diagnostics:render()).is(rendered(text, "flushBytes", message))
			expect(diagnostics.errors).is(0)
			expect(report(schema("option flush = 4\noption flushBytes = 8"))).is("")
			expect(report(schema("option manualReplication = true\noption flushBytes = 8"))).is("")
		end)

		test("V3006 warns about a rate on a Server event", function ()
			local text: string = schema("event E { from: Server, type: Reliable, call: Polling, rate: 5 }")
			local message: string =
				"warning V3006: rate on a Server event has no effect; only client-to-server messages are limited"
			local diagnostics: Diagnostics.Diagnostics = select(2, resolve(text))

			expect(diagnostics:render()).is(rendered(text, "rate", message))
			expect(diagnostics.errors).is(0)
		end)
	end)
end)
