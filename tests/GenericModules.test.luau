--[[
    Proves generics through the generator: each module writes one alias for
    a generic and annotates an instantiation with it, a type parameter that
    would hide a type inside its alias is refused, and an argument's text
    stays out of the way of a failure's
--]]

--!strict
local fs = require("@lune/fs")

local Suite = require("./Suite")
local Generated = require("./Generated")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Targets = require("@volt/Compiler/Targets")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

-- The two options every schema must carry, so a fragment compiles clean
local HEADER: string = `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"\n`

local function holds(text: string, part: string): boolean
	return text:find(part, 1, true) ~= nil
end

describe("Generic modules", function ()
	test("hold one alias per generic, an alias of an instantiation and none for an instantiation", function ()
		local client: string, server: string = Generated.modules("Generics", fs.readFile("tests/Schemas/Generics.volt"))

		for _, text: string in { client, server } do
			expect(holds(text, "export type Pair<A, B> = { first: A, second: B }\n")).is(true)
			expect(holds(text, "\ntype Box<T> = { value: T, spare: { T } }\n")).is(true)
			expect(holds(text, "export type Scores = Pair<number, number>\n")).is(true)
			expect(holds(text, "type Pair_")).is(false)
		end

		expect(holds(server, "): (number, number, Pair<number, number>)\n")).is(true)
	end)

	test("V4002 refuses a parameter named like a type the modules name or a schema label, namespaces walked", function ()
		local text: string = `{HEADER}struct A<Player> \{}\nstruct B<A> \{}\nnamespace N \{ struct C<number> \{} }`
		local file: Schema.File, hash: number, diagnostics = Generated.compile("Bad", text)

		Targets.modules(file, diagnostics, hash)

		expect(diagnostics.errors).is(3)
		expect(holds(diagnostics:render(), `error V4002: "Player" is a type the generated`)).is(true)
		expect(holds(diagnostics:render(), `error V4002: "A" is the label of a named type`)).is(true)
		expect(holds(diagnostics:render(), `error V4002: "number" is a type the generated`)).is(true)
	end)

	test("a literal argument's quote stays out of the text of a failure", function ()
		local text: string =
			`{HEADER}struct Box<T> \{ v: T }\nevent E \{ from: Client, type: Reliable, call: SingleSync, data: (a: Box<"x">, b: Box<"x">) }`
		local module: any = Generated.load("Quoted", Generated.render((Generated.compile("Quoted", text))))
		local ok: boolean, message: any = pcall(module.E.write, { v = "y" }, { v = "x" })

		expect(ok).is(false)
		expect(tostring(message)).is(`Box<'x'>.v: expected "x"`)
	end)
end)
