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
			expect((file.declarations[1] :: any).references).is(1)
		end)

		test("V3003 reports a recursive type once per cycle, at the reference that closes it", function ()
			local text: string = schema("type A = struct { next: A? }\ntype B = C[]\ntype C = struct { b: B }")
			local first: string = rendered(
				text,
				"A",
				`error V3003: "A" contains itself; recursive types are not supported in this version`,
				2
			)
			local second: string = rendered(
				text,
				"B",
				`error V3003: "B" contains itself; recursive types are not supported in this version`,
				2
			)

			expect(report(text)).is(`{first}\n\n{second}`)
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
