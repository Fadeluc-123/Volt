--[[
    Proves recursive types up to the generator: every member of a cycle is
    found and takes its depth, one with no value that ends is refused, a
    generic recurses only with its own parameters, and nothing that walks a
    cycle or a union of itself ever loops. Their sizes are CycleSizes'
--]]

--!strict
local Suite = require("./Suite")
local compiled = require("./Compiled")
local rendered = require("./Rendered")
local Print = require("@volt/Compiler/Analyse/Print")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Sizes = require("@volt/Compiler/Analyse/Sizes")
local Unions = require("@volt/Compiler/Analyse/Unions")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type TypeDeclaration = Schema.TypeDeclaration

-- The two options every schema must carry, so a fragment compiles clean
local HEADER: string = `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"\n`

local TREE: string = "struct Tree { name: string(0..8), kids: Tree[0..3] }\n"
local DEEP: string = `@depth(4) {TREE}`

local ENDS: string =
	"has no finite value: every way through it leads back to it; an optional, a collection that may be empty or another variant on the way ends it"

-- Types no value of which ends, and the name each is refused at
local UNENDING: { { string } } = {
	{ "struct Chain { next: Chain }", "Chain" },
	{ "struct Pairs { kids: Pairs[2] }", "Pairs" },
	{ "struct Least { kids: Least[1..4] }", "Least" },
	{ `enum E "k" \{ Only \{ e: E } }`, "E" },
	{ "struct M { m: { [u8]: M }(1..2) }", "M" },
	{ "type U = U | U", "U" },
}

-- Types that recurse and end
local ENDING: { string } = {
	"struct L { next: L? }",
	"struct T { kids: T[0..2] }",
	"struct T { kids: T[] }",
	"struct T { kids: { [u8]: T } }",
	`enum E "k" \{ Leaf, Node \{ e: E } }`,
	`enum E "k" \{ Leaf \{ x: u8 }, Node \{ e: E } }`,
	"type T = T[] | u8",
}

local function report(text: string): string
	local diagnostics = select(2, compiled(text))
	return diagnostics:render()
end

-- A top-level named type by its name
local function named(file: Schema.File, name: string): TypeDeclaration
	for _, declaration: Schema.Declaration in file.declarations do
		if declaration.kind == "type" and declaration.name == name then
			return declaration
		end
	end

	return error(`no type {name}`)
end

describe("Cycles", function ()
	describe("finding them", function ()
		test("a type that holds itself directly takes the default depth, its references counted", function ()
			local text: string =
				`{HEADER}{TREE}event Scene \{ from: Server, type: Reliable, call: Polling, data: Tree }`
			local file: Schema.File, diagnostics = compiled(text)
			local tree: TypeDeclaration = named(file, "Tree")

			expect(diagnostics:render()).is("")
			expect(tree.depth).is(16)
			expect(tree.references).is(2)
			expect(Sizes.shared(tree)).is(true)
		end)

		test("every member of a cycle is found, one that only another member leads back through among them", function ()
			local text: string = `{HEADER}struct R \{ a: A?, b: B? }\nstruct A \{ r: R? }\nstruct B \{ a: A? }`
			local file: Schema.File, diagnostics = compiled(text)

			expect(diagnostics:render()).is("")
			expect(named(file, "R").depth).is(16)
			expect(named(file, "A").depth).is(16)
			expect(named(file, "B").depth).is(16)
		end)

		test("a type that only reaches a cycle is not in it", function ()
			local text: string = `{HEADER}{TREE}struct Holder \{ tree: Tree? }\ntype Plain = u8`
			local file: Schema.File, diagnostics = compiled(text)

			expect(diagnostics:render()).is("")
			expect(named(file, "Holder").depth).is(nil)
			expect(named(file, "Plain").depth).is(nil)
			expect(Sizes.shared(named(file, "Holder"))).is(false)
		end)

		test("@depth sets a type's own bound, on a cycle's members each alone", function ()
			local text: string =
				`{HEADER}@depth(4) struct Folder \{ entries: Entry[0..3] }\n@depth(7) enum Entry "kind" \{ File \{ size: u16 }, Sub \{ folder: Folder } }`
			local file: Schema.File, diagnostics = compiled(text)

			expect(diagnostics:render()).is("")
			expect(named(file, "Folder").depth).is(4)
			expect(named(file, "Entry").depth).is(7)
			expect((named(file, "Folder").attributes :: Schema.Attributes).depth).is(4)
		end)
	end)

	describe("values that end", function ()
		for _, case: { string } in UNENDING do
			test(`V3003 refuses {case[1]}, at its name`, function ()
				local text: string = `{HEADER}{case[1]}`

				expect(report(text)).is(rendered(text, case[2], `error V3003: "{case[2]}" {ENDS}`))
			end)
		end

		test("V3003 refuses a cycle of plain names at each, and nothing loops on them", function ()
			local text: string = `{HEADER}type A = B\ntype B = A`
			local first: string = rendered(text, "A", `error V3003: "A" {ENDS}`)
			local second: string = rendered(text, "B", `error V3003: "B" {ENDS}`, 2)
			local file: Schema.File = compiled(text)

			expect(report(text)).is(`{first}\n\n{second}`)
			expect(Sizes.resolved(named(file, "A").type).kind).is("reference")
			expect(#Unions.classes(named(file, "A").type)).is(0)
		end)

		test("a struct whose way out goes through another recursive type ends only if that type does", function ()
			local good: string = `{HEADER}struct A \{ b: B }\nstruct B \{ a: A? }`
			local bad: string = `{HEADER}struct A \{ b: B }\nstruct B \{ a: A }`

			expect(report(good)).is("")
			expect(report(bad)).is(
				`{rendered(bad, "A", `error V3003: "A" {ENDS}`)}\n\n{rendered(bad, "B", `error V3003: "B" {ENDS}`, 2)}`
			)
		end)

		for _, written: string in ENDING do
			test(`{written} compiles`, function ()
				expect(report(`{HEADER}{written}`)).is("")
			end)
		end

		test("V3009 refuses a union that is one of its own members, and the compile ends", function ()
			local text: string = `{HEADER}type T = T | u8`
			local message: string = "error V3009: union members T and u8 are both numbers at runtime"

			expect(report(text)).is(rendered(text, "u8", message))
		end)

		test("V3009 refuses a union reached again through another, and classes never loops", function ()
			local text: string = `{HEADER}type A = B | u8\ntype B = A | string`
			local file: Schema.File, diagnostics = compiled(text)
			local classes: { string } = Unions.classes(named(file, "A").type)

			expect(diagnostics.errors > 0).is(true)
			expect(diagnostics:render():find("error V3009", 1, true) ~= nil).is(true)
			expect(table.concat(classes, ",")).is("string,number")
		end)
	end)

	describe("the attribute", function ()
		test("V2012 refuses @depth on an event, a function and a namespace", function ()
			local text: string =
				`{HEADER}@depth(4) event E \{ from: Client, type: Reliable, call: Polling }\n@depth(4) function F \{}\n@depth(4) namespace N \{}`
			local applies: string = `error V2012: "@depth" applies to a type, struct or enum, not to`
			local expected: { string } = {
				rendered(text, "@depth(4)", `{applies} event E`),
				rendered(text, "@depth(4)", `{applies} function F`, 2),
				rendered(text, "@depth(4)", `{applies} namespace N`, 3),
			}

			expect(report(text)).is(table.concat(expected, "\n\n"))
		end)

		test("V2005 refuses @depth with no argument and an argument on an attribute that takes none", function ()
			local text: string = `{HEADER}@depth struct T \{ next: T? }\n@private(4) type P = u8`
			local expected: { string } = {
				rendered(text, "@depth", `error V2005: "@depth" takes a number in parentheses, such as @depth(4)`),
				rendered(text, "@private(4)", `error V2005: "@private" takes no argument`),
			}

			expect(report(text)).is(table.concat(expected, "\n\n"))
		end)

		test("V2005 refuses an argument that is not a number, and recovery keeps the next declaration", function ()
			local text: string = `{HEADER}@depth(x) struct T \{ next: T? }\ntype P = u8`
			local file: Schema.File = compiled(text)

			expect(report(text)).is(rendered(text, "x", `error V2005: expected a number for "@depth", got "x"`, 1))
			expect(named(file, "P").name).is("P")
		end)

		test("V2002 refuses @depth written twice", function ()
			local text: string = `{HEADER}@depth(4) @depth(5) struct T \{ next: T? }`
			local file: Schema.File = compiled(text)

			expect(report(text)).is(rendered(text, "@depth(5)", `error V2002: duplicate attribute "@depth"`))
			expect(named(file, "T").depth).is(4)
		end)

		test("V3005 refuses a depth that is not a whole number from 1 to 1000, at the attribute", function ()
			local cases: { { string } } = {
				{ "0", "@depth must be a positive integer, got 0" },
				{ "-1", "@depth must be a positive integer, got -1" },
				{ "1.5", "@depth must be a positive integer, got 1.5" },
				{ "1001", "@depth must be at most 1000, got 1001" },
			}

			for _, case: { string } in cases do
				local text: string = `{HEADER}@depth({case[1]}) struct T \{ next: T? }`

				expect(report(text)).is(rendered(text, `@depth({case[1]})`, `error V3005: {case[2]}`))
			end
		end)

		test("the ends of the range are taken", function ()
			expect(report(`{HEADER}@depth(1) struct T \{ next: T? }`)).is("")
			expect(report(`{HEADER}@depth(1000) struct T \{ next: T? }`)).is("")
		end)

		test("V3018 refuses @depth on a type that is not recursive, at the attribute", function ()
			local text: string = `{HEADER}@depth(4) struct Stack \{ x: u8 }`
			local message: string = `error V3018: "Stack" is not recursive, so @depth changes nothing`

			expect(report(text)).is(rendered(text, "@depth(4)", message))
		end)

		test("an exported recursive type may carry it, and a private one too", function ()
			local exported: string = `{HEADER}@depth(4) export struct T \{ next: T? }`
			local private: string = `{HEADER}@private @depth(4) struct T \{ next: T? }`

			expect(report(exported)).is("")
			expect(report(private)).is("")
		end)
	end)

	describe("recursion through a generic", function ()
		test("List<T> referring to List<T> is one recursive instantiation", function ()
			local text: string = `{HEADER}struct List<T> \{ value: T, next: List<T>? }\ntype A = List<u8>`
			local file: Schema.File, diagnostics = compiled(text)
			local made: TypeDeclaration = (file.instantiations :: { TypeDeclaration })[1]
			local next: any = (made.type :: any).fields[2].type.inner

			expect(diagnostics:render()).is("")
			expect(made.path).is("List<u8>")
			expect(#(file.instantiations :: { TypeDeclaration })).is(1)
			expect(next.target).is(made)
			expect(made.depth).is(16)
			expect(made.references).is(2)
		end)

		test("V3021 reports a generic referring to itself with other arguments, at that reference", function ()
			local text: string = `{HEADER}struct List<T> \{ value: T, next: List<T[]>? }\ntype A = List<u8>`
			local message: string =
				`error V3021: "List" refers to itself as List<u8[]> inside List<u8>; a generic refers to itself only with its own parameters`

			expect(report(text)).is(rendered(text, "List<T[]>", message))
		end)

		test("V3021 catches two generics growing each other, and a generic nesting itself as an argument", function ()
			local mutual: string = `{HEADER}struct A<T> \{ b: B<T[]>? }\nstruct B<T> \{ a: A<T>? }\ntype X = A<u8>`
			local nested: string = `{HEADER}struct L<T> \{ next: L<L<T>>? }\ntype X = L<u8>`

			expect(report(mutual):find('error V3021: "A" refers to itself as A<u8[]> inside A<u8>', 1, true) ~= nil).is(
				true
			)
			expect(report(nested):find('error V3021: "L" refers to itself as L<L<u8>> inside L<u8>', 1, true) ~= nil).is(
				true
			)
		end)

		test("two generics that hold each other with their own parameters are recursive and clean", function ()
			local text: string = `{HEADER}struct A<T> \{ b: B<T>? }\nstruct B<T> \{ a: A<T>? }\ntype X = A<u8>`
			local file: Schema.File, diagnostics = compiled(text)
			local list: { TypeDeclaration } = file.instantiations :: { TypeDeclaration }

			expect(diagnostics:render()).is("")
			expect(list[1].path).is("A<u8>")
			expect(list[2].path).is("B<u8>")
			expect(list[1].depth).is(16)
			expect(list[2].depth).is(16)
		end)

		test("V3003 reports an instantiation with no value that ends at the reference that first named it", function ()
			local text: string = `{HEADER}struct Chain<T> \{ value: T, next: Chain<T> }\ntype A = Chain<u8>`

			expect(report(text)).is(rendered(text, "Chain<u8>", `error V3003: "Chain<u8>" {ENDS}`))
		end)

		test("@depth on a generic applies to every instantiation, and V3018 when none is recursive", function ()
			local deep: string =
				`{HEADER}@depth(3) struct List<T> \{ next: List<T>? }\ntype A = List<u8>\ntype B = List<u16>`
			local flat: string = `{HEADER}@depth(3) struct Box<T> \{ v: T }\ntype A = Box<u8>\ntype B = Box<u16>`
			local file: Schema.File, diagnostics = compiled(deep)
			local list: { TypeDeclaration } = file.instantiations :: { TypeDeclaration }
			local message: string = `error V3018: "Box" is not recursive, so @depth changes nothing`

			expect(diagnostics:render()).is("")
			expect(list[1].depth).is(3)
			expect(list[2].depth).is(3)
			expect(report(flat)).is(rendered(flat, "@depth(3)", message))
		end)
	end)

	describe("canonical form", function ()
		test("prints @depth before the declaration and ends a recursive type's annotation with its depth", function ()
			local text: string =
				`{HEADER}@depth(4) export {TREE}event Scene \{ from: Client, type: Reliable, call: Polling, data: Tree }`
			local printed: string = Print.file((compiled(text)))
			local line: string =
				"\n@depth(4) export type Tree = struct { name: string(0..8), kids: Tree[0..3] } -- 2..400 bytes, 2 references, depth 4\n"

			expect(printed:find(line, 1, true) ~= nil).is(true)
		end)

		test("@depth changes the hash, and so does its number", function ()
			local plain: number = select(3, compiled(`{HEADER}{TREE}`))
			local four: number = select(3, compiled(`{HEADER}@depth(4) {TREE}`))
			local five: number = select(3, compiled(`{HEADER}@depth(5) {TREE}`))

			expect(plain).never_is(four)
			expect(four).never_is(five)
		end)

		test("@depth prints after the attributes above it in the rows' order, however it is written", function ()
			local one: number = select(3, compiled(`{HEADER}@depth(4) @private struct T \{ next: T? }`))
			local two: number = select(3, compiled(`{HEADER}@private @depth(4) struct T \{ next: T? }`))

			expect(one).is(two)
			expect(
				Print.file((compiled(`{HEADER}@depth(4) @private struct T \{ next: T? }`)))
					:find("\n@private @depth(4) type T", 1, true) ~= nil
			).is(true)
		end)
	end)

	describe("replication", function ()
		test("V3015 refuses a @delta event whose data reaches a recursive type, at the reference", function ()
			local text: string =
				`{HEADER}{DEEP}@delta event a \{ from: Server, type: Reliable, call: Polling, data: struct \{ tree: Tree? } }`
			local message: string = "error V3015: @delta event a cannot carry Tree, which is recursive"

			expect(report(text)).is(rendered(text, "Tree", message, 3))
		end)

		test("V3015 refuses a @delta event whose struct is itself recursive", function ()
			local text: string =
				`{HEADER}@depth(4) struct Node \{ next: Node? }\n@delta event a \{ from: Server, type: Reliable, call: Polling, data: Node }`
			local message: string = "error V3015: @delta event a cannot carry Node, which is recursive"

			expect(report(text)).is(rendered(text, "Node", message, 3))
		end)
	end)

	test("an AwaitedInstance a cycle reaches is refused once, and the walk ends", function ()
		local text: string =
			`{HEADER}@depth(4) struct T \{ part: AwaitedInstance(Model)?, next: T? }\nevent E \{ from: Client, type: Reliable, call: Polling, data: T }`
		local diagnostics = select(2, compiled(text))

		expect(diagnostics.errors).is(1)
		expect(diagnostics:render():find("error V3022", 1, true) ~= nil).is(true)
	end)

	test("a @dictionary type a cycle reaches is refused once, and the walk ends", function ()
		local text: string =
			`{HEADER}@dictionary type Item = string(1..8)\n@depth(4) struct T \{ item: Item, next: T? }\nevent E \{ from: Client, type: Reliable, call: Polling, data: T }`
		local diagnostics = select(2, compiled(text))

		expect(diagnostics.errors).is(1)
		expect(diagnostics:render():find("error V3017", 1, true) ~= nil).is(true)
	end)
end)
