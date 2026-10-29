--[[
    Proves every declaration form parses into the node the design describes
    by printing it back to source, that the attributes in front of one land
    in its set wherever they stand, that each attribute diagnostic is
    reported at the attribute, and that recovery keeps the next attribute
--]]

--!strict
local Suite = require("./Suite")
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

type Declaration = Schema.Declaration
type Set = { [string]: boolean }

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
	{
		"namespace Combat { event Hit { from: Client, type: Reliable, call: SingleSync } namespace Inner { type Id = u8 } }",
		"namespace Combat {\n\tevent Hit { from: Client, type: Reliable, call: SingleSync }\n\tnamespace Inner {\n\t\ttype Id = u8\n\t}\n}",
	},
	{ "@private type Cursor = u16(0..4096)" },
	{ "@private struct Page { first: u16 }", "@private type Page = struct { first: u16 }" },
	{ "namespace Ui { @private enum Mode { On } }", "namespace Ui {\n\t@private type Mode = enum { On }\n}" },
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

-- The attributes a parsed declaration carries, as the schema node holds them
local function attributesOf(declaration: Declaration): Set?
	return declaration.kind == "type" and declaration.attributes or nil
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
			local message: string = `error V2011: unknown attribute "@stable"; attributes are @private`

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
