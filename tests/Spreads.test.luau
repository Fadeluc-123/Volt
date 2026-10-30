--[[
    Proves struct spread: an entry parses in a struct or variant body and
    nowhere else, stands for its struct's fields at its own place, and leaves
    a schema exactly as if the fields were written out, so its modules and
    hash match; a duplicate field and a spread of no struct are refused
--]]

--!strict
local Suite = require("./Suite")
local compiled = require("./Compiled")
local Generated = require("./Generated")
local rendered = require("./Rendered")
local Diagnostics = require("@volt/Compiler/Diagnostics")
local Lexer = require("@volt/Compiler/Lexer")
local Parser = require("@volt/Compiler/Parser")
local Print = require("@volt/Compiler/Analyse/Print")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Source = require("@volt/Compiler/Source")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

-- The two options every schema must carry, so a fragment compiles clean
local HEADER: string = `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"\n`

local PAIR: string = "struct Pair<A, B> { first: A, second: B }\n"
local BASE: string = "struct Base { id: u16, name: string(0..16) }\n"

-- The message a schema carries, the one thing that differs between its two spellings being how Unit is written
local MOVED: string = "event Moved { from: Client, type: Reliable, call: SingleSync, data: Unit }\n"

-- The parsed tree printed back as written, before anything expands it
local function parsed(text: string): (string, Diagnostics.Diagnostics)
	local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(Source.new("Test.volt", text))
	local file: Schema.File = Parser.parse(Lexer.scan(diagnostics.source, diagnostics), diagnostics)

	return Print.file({ options = { spans = {} }, declarations = file.declarations }), diagnostics
end

local function report(text: string): string
	local diagnostics: Diagnostics.Diagnostics = select(2, compiled(text))
	return diagnostics:render()
end

-- The field names of a named type or an enum's variant, in order
local function names(fields: { Schema.Field }): string
	local list: { string } = {}
	for _, field: Schema.Field in fields do
		table.insert(list, field.name)
	end
	return table.concat(list, ",")
end

local function fieldsOf(file: Schema.File, index: number): { Schema.Field }
	local declaration: Schema.TypeDeclaration = file.declarations[index] :: Schema.TypeDeclaration
	return (declaration.type :: any).fields
end

describe("Spreads", function ()
	describe("parse", function ()
		test("a spread is an entry of a struct body and of a variant body, printed back as written", function ()
			local text: string =
				`struct S \{ ..Base, ..Pair<u8, u8>, x: u8 }\nenum Hit "kind" \{ Melee \{ ..Base, damage: u16 }, Miss }`
			local printed: string, diagnostics = parsed(text)
			local expected: string =
				`type S = struct \{ ..Base, ..Pair<u8, u8>, x: u8 }\ntype Hit = enum "kind" \{ Melee \{ ..Base, damage: u16 }, Miss }`

			expect(diagnostics:render()).is("")
			expect(printed).is(expected)
		end)

		test("V2001 refuses a spread in a pack, at the ..", function ()
			local text: string = "event E { from: Client, type: Reliable, call: Polling, data: (..Base) }"
			local diagnostics: Diagnostics.Diagnostics = select(2, parsed(text))

			expect(diagnostics:render()).is(
				rendered(text, "..", "error V2001: a parameter pack cannot spread a struct")
			)
		end)

		test("V2001 refuses anything but a reference after the .., at what follows it", function ()
			for _, written: string in { "u8", "Vector3", "true", "{ x: u8 }" } do
				local text: string = `struct S \{ ..{written} }`
				local diagnostics: Diagnostics.Diagnostics = select(2, parsed(text))
				local needle: string = written:sub(1, 1) == "{" and "{" or written
				local nth: number = written:sub(1, 1) == "{" and 2 or 1

				expect(diagnostics:render()).is(
					rendered(text, needle, `error V2001: expected a struct's name after ".."`, nth)
				)
			end
		end)
	end)

	describe("expansion", function ()
		test("fields land at the spread's place, in the order the spread struct declares them", function ()
			local text: string = `{HEADER}{BASE}struct Unit \{ team: u8, ..Base, level: u8 }`
			local file: Schema.File, diagnostics = compiled(text)
			local fields: { Schema.Field } = fieldsOf(file, 2)

			expect(diagnostics:render()).is("")
			expect(names(fields)).is("team,id,name,level")
			expect(fields[2].spread).is(nil)
		end)

		test("a variant's body spreads too, and a struct's own spreads are expanded first", function ()
			local text: string =
				`{HEADER}struct Top \{ ..Mid, c: u8 }\nstruct Mid \{ ..Low, b: u8 }\nstruct Low \{ a: u8 }\nenum Hit "kind" \{ Melee \{ ..Top, d: u8 }, Miss }`
			local file: Schema.File, diagnostics = compiled(text)
			local hit: any = (file.declarations[4] :: Schema.TypeDeclaration).type

			expect(diagnostics:render()).is("")
			expect(names(fieldsOf(file, 1))).is("a,b,c")
			expect(names(hit.variants[1].fields)).is("a,b,c,d")
		end)

		test("a spread in a message's inline struct is expanded", function ()
			local text: string =
				`{HEADER}{BASE}event E \{ from: Client, type: Reliable, call: Polling, data: struct \{ ..Base, x: u8 } }`
			local file: Schema.File, diagnostics = compiled(text)
			local event: any = file.declarations[2]

			expect(diagnostics:render()).is("")
			expect(names(event.data.fields)).is("id,name,x")
		end)

		test(
			"the copies are separate types, each counted, so a named type a spread copies is referenced again",
			function ()
				local text: string = `{HEADER}type Id = u8\nstruct Base \{ id: Id }\nstruct Unit \{ ..Base }`
				local file: Schema.File, diagnostics = compiled(text)
				local id: Schema.TypeDeclaration = file.declarations[1] :: Schema.TypeDeclaration
				local base: { Schema.Field } = fieldsOf(file, 2)
				local unit: { Schema.Field } = fieldsOf(file, 3)

				expect(diagnostics:render()).is("")
				expect(id.references).is(2)
				expect(rawequal(base[1], unit[1])).is(false)
				expect(rawequal(base[1].type, unit[1].type)).is(false)
			end
		)

		test("a generic struct's parameters take the spread's arguments", function ()
			local text: string = `{HEADER}{PAIR}struct Unit \{ ..Pair<u8, string(0..4)>, x: u8 }`
			local file: Schema.File, diagnostics = compiled(text)
			local fields: { Schema.Field } = fieldsOf(file, 2)

			expect(diagnostics:render()).is("")
			expect(names(fields)).is("first,second,x")
			expect(Print.type(fields[1].type)).is("u8")
			expect(Print.type(fields[2].type)).is("string(0..4)")
		end)

		test("a spread of Pair<A, B> inside Triple<A, B, C> keeps the parameters", function ()
			local text: string =
				`{HEADER}{PAIR}struct Triple<A, B, C> \{ ..Pair<A, B>, third: C }\ntype T = Triple<u8, u16, u32>`
			local file: Schema.File, diagnostics = compiled(text)
			local printed: string = Print.file(file)
			local line: string = "\ntype Triple<A, B, C> = struct { first: A, second: B, third: C }\n"
			local made: any = (file.instantiations :: { Schema.TypeDeclaration })[1]

			expect(diagnostics:render()).is("")
			expect(printed:find(line, 1, true) ~= nil).is(true)
			expect(made.path).is("Triple<u8, u16, u32>")
			expect(Print.type(made.type)).is("struct { first: u8, second: u16, third: u32 }")
		end)

		test("a schema with spreads compiles to the modules and the hash of the fields written out", function ()
			local spread: string = `{HEADER}{BASE}struct Unit \{ ..Base, team: u8 }\n{MOVED}`
			local written: string = `{HEADER}{BASE}struct Unit \{ id: u16, name: string(0..16), team: u8 }\n{MOVED}`
			local client: string, server: string, types: string = Generated.modules("Spreads", spread)
			local plainClient: string, plainServer: string, plainTypes: string = Generated.modules("Spreads", written)

			expect(client).is(plainClient)
			expect(server).is(plainServer)
			expect(types).is(plainTypes)
		end)

		test("so does a spread of a generic struct, by the hash", function ()
			local spread: string = `{HEADER}{PAIR}struct Unit \{ ..Pair<u8, u16>, x: u8 }`
			local written: string = `{HEADER}{PAIR}struct Unit \{ first: u8, second: u16, x: u8 }`

			expect(select(3, compiled(spread))).is(select(3, compiled(written)))
		end)

		test("an edit to the spread struct changes the hash of what spreads it", function ()
			local before: string = `{HEADER}{BASE}struct Unit \{ ..Base }`
			local after: string = `{HEADER}struct Base \{ id: u32, name: string(0..16) }\nstruct Unit \{ ..Base }`

			expect(select(3, compiled(before))).never_is(select(3, compiled(after)))
		end)
	end)

	describe("diagnostics", function ()
		test("V3020 reports a field a spread brought that is also written, at the second", function ()
			local text: string = `{HEADER}{BASE}struct Unit \{ ..Base, id: u8 }`
			local message: string = `error V3020: field "id" comes twice in Unit, from ..Base and as written`

			expect(report(text)).is(rendered(text, "id: u8", message))
		end)

		test("V3020 reports a written field a spread then brings, at the spread", function ()
			local text: string = `{HEADER}{BASE}struct Unit \{ id: u8, ..Base }`
			local message: string = `error V3020: field "id" comes twice in Unit, as written and from ..Base`

			expect(report(text)).is(rendered(text, "..Base", message))
		end)

		test("V3020 reports a field two spreads bring, at the second, and keeps the first", function ()
			local text: string = `{HEADER}struct A \{ x: u8 }\nstruct B \{ x: u16, y: u8 }\nstruct C \{ ..A, ..B }`
			local file: Schema.File = compiled(text)
			local message: string = `error V3020: field "x" comes twice in C, from ..A and from ..B`

			expect(report(text)).is(rendered(text, "..B", message))
			expect(Print.type(fieldsOf(file, 3)[1].type)).is("u8")
			expect(names(fieldsOf(file, 3))).is("x,y")
		end)

		test("V3020 names a variant's body by its enum and variant", function ()
			local text: string = `{HEADER}{BASE}enum Hit "kind" \{ Melee \{ ..Base, id: u8 } }`
			local message: string = `error V3020: field "id" comes twice in Hit.Melee, from ..Base and as written`

			expect(report(text)).is(rendered(text, "id: u8", message))
		end)

		test("V3019 refuses a spread of an enum, a union alias and a type parameter, at the spread", function ()
			local cases: { { string } } = {
				{ "enum Team { Red }\nstruct S { ..Team }", "..Team", `"Team" is an enum` },
				{ "type U = u8 | string\nstruct S { ..U }", "..U", `"U" is a union` },
				{ "struct G<T> { ..T }", "..T", `"T" is a type parameter` },
				{ "type Id = u8\nstruct S { ..Id }", "..Id", `"Id" is a primitive` },
				{ "struct B { x: u8 }\ntype Alias = B\nstruct S { ..Alias }", "..Alias", `"Alias" is an alias` },
			}

			for _, case: { string } in cases do
				local text: string = `{HEADER}{case[1]}`

				expect(report(text)).is(rendered(text, case[2], `error V3019: a spread takes a struct, and {case[3]}`))
			end
		end)

		test("V3019 refuses a struct spreading itself, directly and through another", function ()
			local direct: string = `{HEADER}struct S \{ ..S }`
			local through: string = `{HEADER}struct A \{ ..B }\nstruct B \{ ..A }`

			expect(report(direct)).is(rendered(direct, "..S", `error V3019: "S" spreads itself`))
			expect(report(through)).is(rendered(through, "..A", `error V3019: "A" spreads itself through "B"`))
		end)

		test("V3007 reports a spread with the wrong argument count, and drops it with no second error", function ()
			local text: string = `{HEADER}{PAIR}struct S \{ ..Pair<u8>, x: u8 }`
			local file: Schema.File = compiled(text)

			expect(report(text)).is(rendered(text, "Pair<u8>", `error V3007: "Pair" takes 2 type arguments, got 1`))
			expect(names(fieldsOf(file, 2))).is("x")
		end)

		test("V3001 reports a spread of an unknown name, and drops it with no second error", function ()
			local text: string = `{HEADER}struct S \{ ..Missing, x: u8 }`

			expect(report(text)).is(rendered(text, "Missing", `error V3001: unknown type "Missing"`))
		end)
	end)
end)
