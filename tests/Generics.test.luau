--[[
    Proves generics up to the generator: parameters and arguments parse,
    resolve and count, each distinct argument list is one instantiation with
    its own path and label, a generic is judged through its instantiations,
    and the canonical form prints the template and its references
--]]

--!strict
local Suite = require("./Suite")
local compiled = require("./Compiled")
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

type TypeDeclaration = Schema.TypeDeclaration

-- The two options every schema must carry, so a fragment compiles clean
local HEADER: string = `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"\n`

local PAIR: string = "struct Pair<A, B> { first: A, second: B }\n"

local function parse(text: string): (Schema.File, Diagnostics.Diagnostics)
	local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(Source.new("Test.volt", text))
	local file: Schema.File = Parser.parse(Lexer.scan(diagnostics.source, diagnostics), diagnostics)

	return file, diagnostics
end

local function parseReport(text: string): string
	local diagnostics: Diagnostics.Diagnostics = select(2, parse(text))
	return diagnostics:render()
end

local function report(text: string): string
	local diagnostics: Diagnostics.Diagnostics = select(2, compiled(text))
	return diagnostics:render()
end

-- Every instantiation's path, in the order references first named them
local function paths(file: Schema.File): string
	local list: { string } = {}
	for _, instantiation: TypeDeclaration in file.instantiations or {} do
		table.insert(list, instantiation.path :: string)
	end
	return table.concat(list, ",")
end

-- The instantiation made first, which most cases make only one of
local function first(file: Schema.File): TypeDeclaration
	return (file.instantiations :: { TypeDeclaration })[1]
end

describe("Generics", function ()
	describe("parse", function ()
		test("a reference takes arguments, any types, and set<Pair<u8, u8>> closes on its >>", function ()
			local file: Schema.File, diagnostics = parse("type A = Pair<u8, string(0..4)>\ntype B = set<Pair<u8, u8>>")
			local a: any = (file.declarations[1] :: TypeDeclaration).type
			local b: any = (file.declarations[2] :: TypeDeclaration).type

			expect(diagnostics:render()).is("")
			expect(a.kind).is("reference")
			expect(#a.arguments).is(2)
			expect(Print.type(a.arguments[2])).is("string(0..4)")
			expect(b.kind).is("set")
			expect(b.element.name).is("Pair")
			expect(Print.type(b)).is("set<Pair<u8, u8>>")
		end)

		test("a trailing comma closes a parameter list and an argument list", function ()
			local file: Schema.File, diagnostics = parse("struct P<A, B,> { a: A }\ntype T = P<u8, u8,>")
			local parameters: { Schema.Parameter } = (file.declarations[1] :: TypeDeclaration).parameters :: any

			expect(diagnostics:render()).is("")
			expect(#parameters).is(2)
			expect(#((file.declarations[2] :: TypeDeclaration).type :: any).arguments).is(2)
		end)

		test("a type, a struct and an enum carry their parameters, each with its span, and @private lands", function ()
			local text: string =
				`type Maybe<T> = T?\nstruct Pair<A, B> \{ first: A, second: B }\n@private enum Result<T> "kind" \{ Ok \{ value: T }, Failed }\ntype Plain = u8`
			local file: Schema.File, diagnostics = parse(text)
			local maybe: TypeDeclaration = file.declarations[1] :: TypeDeclaration
			local pair: TypeDeclaration = file.declarations[2] :: TypeDeclaration
			local result: TypeDeclaration = file.declarations[3] :: TypeDeclaration
			local plain: TypeDeclaration = file.declarations[4] :: TypeDeclaration

			expect(diagnostics:render()).is("")
			expect((maybe.parameters :: { Schema.Parameter })[1].name).is("T")
			expect((pair.parameters :: { Schema.Parameter })[2].name).is("B")
			expect((pair.parameters :: { Schema.Parameter })[2].start).is((text:find("B>", 1, true)))
			expect((result.parameters :: { Schema.Parameter })[1].name).is("T")
			expect((result.attributes :: Schema.Attributes).private).is(true)
			expect(plain.parameters).is(nil)
		end)

		test("V2002 reports a type parameter named twice and keeps the first", function ()
			local text: string = "struct P<A, A> { x: A }"
			local file: Schema.File = parse(text)

			expect(parseReport(text)).is(rendered(text, "A", `error V2002: duplicate type parameter "A"`, 2))
			expect(#((file.declarations[1] :: TypeDeclaration).parameters :: { Schema.Parameter })).is(1)
		end)

		test("V2013 reports type parameters on an exported declaration, at the <", function ()
			local text: string = "export struct P<A> {}\nexport type Q<A> = A"
			local message: string =
				"error V2013: an exported type cannot take type parameters; export an instantiation, as export type Scores = Pair<u16, u16>"

			expect(parseReport(text)).is(`{rendered(text, "<", message)}\n\n{rendered(text, "<", message, 2)}`)
		end)

		test("V2001 reports type parameters on an event, a function and a namespace", function ()
			for _, text: string in { "event E<T> {}", "function F<T> {}", "namespace N<T> {}" } do
				expect(parseReport(text)).is(rendered(text, "<", `error V2001: expected "\{", got "<"`))
			end
		end)

		test("an empty list is refused, since a parameter or an argument is what opens it", function ()
			local declared: string = "struct P<> {}"
			local referred: string = "type T = P<>"

			expect(parseReport(declared)).is(rendered(declared, ">", `error V2001: expected a name, got ">"`))
			expect(parseReport(referred)).is(rendered(referred, ">", `error V2001: expected a type, got ">"`))
		end)
	end)

	describe("resolve", function ()
		test("a parameter is bound by its index, with no target, and hides a top-level type of its name", function ()
			local text: string = `{HEADER}type T = string(0..4)\nstruct Box<T> \{ value: T }\ntype B = Box<u8>`
			local file: Schema.File, diagnostics = compiled(text)
			local box: any = (file.declarations[2] :: TypeDeclaration).type
			local top: TypeDeclaration = file.declarations[1] :: TypeDeclaration

			expect(diagnostics:render()).is("")
			expect(box.fields[1].type.parameter).is(1)
			expect(box.fields[1].type.target).is(nil)
			expect(top.references).is(0)
			expect(Print.type(first(file).type)).is("struct { value: u8 }")
		end)

		test("an argument is bound where the reference is written, through the namespace rules", function ()
			local text: string =
				`{HEADER}{PAIR}namespace Inv \{ struct Stack \{ x: u8 }\ntype A = Pair<Stack, u8> }\ntype B = Pair<Inv.Stack, u8>`
			local file: Schema.File, diagnostics = compiled(text)

			expect(diagnostics:render()).is("")
			expect(paths(file)).is("Pair<Inv.Stack, u8>")
			expect(first(file).references).is(2)
		end)

		test(
			"V3007 reports a wrong argument count, arguments for a type that takes none, and for a parameter",
			function ()
				local text: string =
					`{HEADER}{PAIR}struct Stack \{ x: u8 }\ntype A = Pair<u8>\ntype B = Pair\ntype C = Stack<u8>\nstruct G<T> \{ v: T<u8> }`
				local expected: { string } = {
					rendered(text, "Pair<u8>", `error V3007: "Pair" takes 2 type arguments, got 1`),
					rendered(text, "Pair", `error V3007: "Pair" takes 2 type arguments, got 0`, 3),
					rendered(text, "Stack<u8>", `error V3007: "Stack" takes no type arguments, got 1`),
					rendered(text, "T<u8>", `error V3007: type parameter "T" takes no type arguments`),
				}

				expect(report(text)).is(table.concat(expected, "\n\n"))
			end
		)
	end)

	describe("instantiations", function ()
		test("one argument list written twice is one instantiation with two references", function ()
			local text: string = `{HEADER}{PAIR}type A = Pair<u8, u8>\nstruct B \{ p: Pair<u8, u8> }`
			local file: Schema.File, diagnostics = compiled(text)
			local made: TypeDeclaration = first(file)
			local a: any = (file.declarations[2] :: TypeDeclaration).type
			local b: any = (file.declarations[3] :: TypeDeclaration).type

			expect(diagnostics:render()).is("")
			expect(paths(file)).is("Pair<u8, u8>")
			expect(made.references).is(2)
			expect(made.label).is("Pair_1")
			expect(made.generic).is(file.declarations[1])
			expect(#(made.arguments :: { Schema.Type })).is(2)
			expect(a.target).is(made)
			expect(b.fields[1].type.target).is(made)
			expect((file.declarations[1] :: TypeDeclaration).references).is(0)
		end)

		test("each distinct argument list is its own, labelled in the order references name them", function ()
			local text: string = `{HEADER}{PAIR}type A = Pair<u8, u16>\ntype B = Pair<u16, u8>\ntype C = Pair<u8, u16>`
			local file: Schema.File = compiled(text)
			local list: { TypeDeclaration } = file.instantiations :: { TypeDeclaration }

			expect(paths(file)).is("Pair<u8, u16>,Pair<u16, u8>")
			expect(list[1].label).is("Pair_1")
			expect(list[2].label).is("Pair_2")
		end)

		test("a label skips a named type that holds it, and a namespaced generic's starts from its path", function ()
			local text: string =
				`{HEADER}{PAIR}type Pair_1 = u8\nnamespace Inv \{ struct Box<T> \{ v: T } }\ntype A = Pair<u8, u8>\ntype B = Inv.Box<u8>`
			local file: Schema.File, diagnostics = compiled(text)
			local list: { TypeDeclaration } = file.instantiations :: { TypeDeclaration }

			expect(diagnostics:render()).is("")
			expect(list[1].label).is("Pair_2")
			expect(list[2].label).is("Inv_Box_1")
			expect(list[2].path).is("Inv.Box<u8>")
		end)

		test("an instantiation spans the reference that first named it and takes its generic's attributes", function ()
			local text: string = `{HEADER}@private struct Box<T> \{ v: T }\ntype A = Box<u8>\ntype B = Box<u8>`
			local file: Schema.File = compiled(text)
			local made: TypeDeclaration = first(file)

			expect(made.start).is((text:find("Box<u8>", 1, true)))
			expect((made.attributes :: Schema.Attributes).private).is(true)
			expect(made.export).is(false)
		end)

		test("a generic body's reference with its parameters makes the instantiation of its arguments", function ()
			local text: string = `{HEADER}{PAIR}struct W<T> \{ p: Pair<T, u8> }\ntype A = W<u16>`
			local file: Schema.File, diagnostics = compiled(text)

			expect(diagnostics:render()).is("")
			expect(paths(file)).is("W<u16>,Pair<u16, u8>")
			expect(Print.type(first(file).type)).is("struct { p: Pair<u16, u8> }")
		end)

		test("an argument's reference is met first, and counts once, through the body that holds it", function ()
			local text: string =
				`{HEADER}{PAIR}type Maybe<T> = T?\nevent Moved \{ from: Client, type: Reliable, call: SingleSync, data: (path: Pair<u8, u8>[0..32], target: Maybe<Pair<u8, u8>>) }`
			local file: Schema.File, diagnostics = compiled(text)
			local list: { TypeDeclaration } = file.instantiations :: { TypeDeclaration }

			expect(diagnostics:render()).is("")
			expect(paths(file)).is("Pair<u8, u8>,Maybe<Pair<u8, u8>>")
			expect(list[1].references).is(2)
			expect(list[2].references).is(1)
		end)

		test("a type argument a generic never uses counts nothing", function ()
			local text: string = `{HEADER}type Id = u8\nstruct Tag<T> \{ x: u8 }\ntype A = Tag<Id>`
			local file: Schema.File = compiled(text)

			expect((file.declarations[1] :: TypeDeclaration).references).is(0)
		end)

		test("a generic's body counts once per instantiation and never for itself", function ()
			local text: string =
				`{HEADER}type Id = u8\nstruct Box<T> \{ id: Id, v: T }\ntype A = Box<u8>\ntype B = Box<u16>`
			local file: Schema.File = compiled(text)

			expect((file.declarations[1] :: TypeDeclaration).references).is(2)
		end)

		test("a generic nothing instantiates makes nothing, and its body is never judged", function ()
			local text: string = `{HEADER}struct K<T> \{ m: \{ [T]: u8 }, bad: u8(9..1) }`
			local file: Schema.File, diagnostics = compiled(text)

			expect(diagnostics:render()).is("")
			expect(paths(file)).is("")
		end)

		test("outside a generic's body no reference targets a generic", function ()
			local text: string = `{HEADER}{PAIR}struct W<T> \{ p: Pair<T, u8>[] }\ntype A = W<Pair<u8, u8>>?`
			local file: Schema.File = compiled(text)

			local function walk(node: Schema.Type | Schema.Pack)
				if node.kind == "reference" and node.target then
					expect(node.target.parameters).is(nil)
				end

				for _, child: Schema.Type in Parser.children(node) do
					walk(child)
				end
			end

			walk((file.declarations[3] :: TypeDeclaration).type)

			for _, instantiation: TypeDeclaration in file.instantiations :: { TypeDeclaration } do
				walk(instantiation.type)
			end
		end)
	end)

	describe("analysis", function ()
		test("a bad range in a generic's body, used by two instantiations, is reported once", function ()
			local text: string = `{HEADER}struct K<T> \{ v: T, bad: u8(9..1) }\ntype A = K<u8>\ntype B = K<u16>`
			local file: Schema.File, diagnostics = compiled(text)

			expect(#(file.instantiations :: { TypeDeclaration })).is(2)
			expect(diagnostics.errors).is(1)
			expect(diagnostics:render()).is(
				rendered(text, "9..1", "error V3011: a range's minimum is above its maximum")
			)
		end)

		test("a check that depends on an argument judges the argument, at the argument", function ()
			local text: string = `{HEADER}struct K<T> \{ m: \{ [T]: u8 } }\ntype A = K<f32[]>`
			local message: string = "error V3008: a map key must be a primitive, string, enum or Roblox type, got f32[]"

			expect(report(text)).is(rendered(text, "f32[]", message))
		end)

		test("a union member an argument makes ambiguous is V3009, and a Roblox argument V3007", function ()
			local union: string = `{HEADER}type Either<T> = T | u8\ntype A = Either<u16>`
			local vector: string = `{HEADER}type V<T> = Vector3<T>\ntype A = V<string>`

			expect(report(union):find("error V3009", 1, true) ~= nil).is(true)
			expect(report(vector):find("error V3007", 1, true) ~= nil).is(true)
		end)

		test("an instantiation of the same shape sizes as the struct it stands for", function ()
			local text: string =
				`{HEADER}{PAIR}event E \{ from: Client, type: Reliable, call: Polling, data: Pair<u8, u16> }`
			local plain: string =
				`{HEADER}{PAIR}event E \{ from: Client, type: Reliable, call: Polling, data: struct \{ first: u8, second: u16 } }`
			local line: string = "payload 3 bytes"

			expect(Print.file((compiled(text))):find(line, 1, true) ~= nil).is(true)
			expect(Print.file((compiled(plain))):find(line, 1, true) ~= nil).is(true)
		end)

		test("V3016 refuses a @dictionary generic, whose id table is one per schema", function ()
			local text: string = `{HEADER}@dictionary type D<T> = string(0..4)`
			local message: string =
				"error V3016: @dictionary type D cannot take type parameters; its id table is one per schema"

			expect(report(text)).is(rendered(text, "D", message))
		end)
	end)

	describe("canonical form", function ()
		test("prints a generic with its parameters and no annotation, and a reference as its path", function ()
			local text: string = `{HEADER}{PAIR}namespace N \{ struct S \{ x: u8 } }\ntype A = Pair<u8, N.S>`
			local printed: string = Print.file((compiled(text)))

			expect(printed:find("\ntype Pair<A, B> = struct { first: A, second: B }\n", 1, true) ~= nil).is(true)
			expect(printed:find("\ntype A = Pair<u8, N.S> -- 1 byte", 1, true) == nil).is(true)
			expect(printed:find("\ntype A = Pair<u8, N.S> -- 2 bytes, 0 references", 1, true) ~= nil).is(true)
		end)

		test("the hash changes with a generic's body and with an argument", function ()
			local base: number = select(3, compiled(`{HEADER}{PAIR}type A = Pair<u8, u8>`))
			local body: number =
				select(3, compiled(`{HEADER}struct Pair<A, B> \{ first: B, second: A }\ntype A = Pair<u8, u8>`))
			local argument: number = select(3, compiled(`{HEADER}{PAIR}type A = Pair<u8, u16>`))

			expect(base).never_is(body)
			expect(base).never_is(argument)
		end)

		test("two spellings of one argument list print alike, so their hash is one", function ()
			local tight: number = select(3, compiled(`{HEADER}{PAIR}type A = Pair<u8,u8>`))
			local loose: number = select(3, compiled(`{HEADER}{PAIR}type A = Pair< u8 , u8 , >`))

			expect(tight).is(loose)
		end)
	end)
end)
