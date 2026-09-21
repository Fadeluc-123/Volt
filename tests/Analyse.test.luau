--[[
    Proves analysis sizes every type form by the wire rules, assigns ids in
    declaration order per direction, reports each V30xx rule where it is
    broken, prints the canonical form, and hashes it so that comments and
    whitespace change nothing and a wire edit changes everything
--]]

--!strict
local fs = require("@lune/fs")

local Suite = require("./Suite")
local rendered = require("./Rendered")
local Analyse = require("@volt/Compiler/Analyse")
local Diagnostics = require("@volt/Compiler/Diagnostics")
local Lexer = require("@volt/Compiler/Lexer")
local Parser = require("@volt/Compiler/Parser")
local Resolve = require("@volt/Compiler/Resolve")
local Source = require("@volt/Compiler/Source")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

-- The two options every schema must carry, so a fragment compiles clean
local HEADER: string = `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"\n`
local EXAMPLE: string = fs.readFile("tests/Schemas/Example.volt") -- The design's complete example

-- Named types the size rows refer to
local NAMED: string =
	"struct Stack { item: string(1..32), quantity: u16(1..999), properties: unknown? }\nenum Team { Red, Blue }\n"

-- Every type form with its least and most bytes, its flag bits and its most side-array slots
local SIZES: { { any } } = {
	{ "u8", 1, 1, 0, 0 },
	{ "u24", 3, 3, 0, 0 },
	{ "i64", 8, 8, 0, 0 },
	{ "f16", 2, 2, 0, 0 },
	{ "q8(0..1)", 1, 1, 0, 0 },
	{ "q16(-1..1)", 2, 2, 0, 0 },
	{ "boolean", 0, 0, 1, 0 },
	{ "unknown", 0, 0, 1, 1 },
	{ "unknown?", 0, 0, 1, 1 },
	{ "string", 2, 65537, 0, 0 },
	{ "string(8)", 8, 8, 0, 0 },
	{ "string(0..64)", 1, 65, 0, 0 },
	{ "string(1..64)", 2, 65, 0, 0 },
	{ "string(0..256)", 2, 258, 0, 0 },
	{ "buffer(16)", 16, 16, 0, 0 },
	{ "Vector3", 12, 12, 0, 0 },
	{ "Vector3<q16(-1024..1024)>", 6, 6, 0, 0 },
	{ "Vector2<f16>", 4, 4, 0, 0 },
	{ "CFrame", 24, 24, 0, 0 },
	{ "CFrame<f32, f16>", 18, 18, 0, 0 },
	{ "AlignedCFrame", 13, 13, 0, 0 },
	{ "AlignedCFrame<i16>", 7, 7, 0, 0 },
	{ "Color3", 3, 3, 0, 0 },
	{ "BrickColor", 2, 2, 0, 0 },
	{ "DateTimeMillis", 8, 8, 0, 0 },
	{ "Instance", 0, 0, 0, 1 },
	{ "Instance(Part)", 0, 0, 0, 1 },
	{ "Instance?", 0, 0, 1, 1 },
	{ "StreamedInstance(Model)", 0, 0, 0, 1 },
	{ "Enum.Material", 2, 2, 0, 0 },
	{ "EnumItem", 4, 258, 0, 0 },
	{ "Stack", 4, 35, 1, 1 },
	{ "Team", 0, 0, 1, 0 },
	{ "u8?", 0, 1, 1, 0 },
	{ "boolean?", 0, 1, 1, 0 },
	{ "Stack?", 0, 36, 1, 1 },
	{ "u8[]", 2, 65537, 0, 0 },
	{ "u8[4]", 4, 4, 0, 0 },
	{ "u8[0..4]", 1, 5, 0, 0 },
	{ "Stack[0..256]", 2, 9218, 0, 256 },
	{ "boolean[8]", 0, 0, 8, 0 },
	{ "boolean[0..16]", 1, 3, 0, 0 },
	{ "boolean[]", 2, 8194, 0, 0 },
	{ "{ [u8]: Stack }(0..64)", 1, 2369, 0, 64 },
	{ "set<u8>(0..64)", 1, 65, 0, 0 },
	{ "set<Team>", 2, 65537, 0, 0 },
	{ "struct { a: u8, b: string(1..4)? }", 1, 6, 1, 0 },
	{ "enum { A, B, C }", 0, 0, 2, 0 },
	{ "enum { A }", 0, 0, 0, 0 },
	{ `enum "kind" \{ A \{ x: u8 }, B \{ y: u16, z: boolean? } }`, 1, 4, 1, 0 },
	{ "u8 | string", 1, 65537, 1, 0 },
	{ "Vector3 | Stack", 5, 36, 1, 1 },
}

-- A discriminant with more variants than a byte holds is two raw bytes
local MANY: { string } = {}
for index: number = 1, 257 do
	table.insert(MANY, `V{index}`)
end
table.insert(SIZES, { `enum \{ {table.concat(MANY, ", ")} }`, 2, 2, 0, 0 } :: { any })

local function schema(fragment: string): string
	return `{HEADER}{fragment}`
end

--[[
    Runs a text through every stage, returning the file, its diagnostics
    and the schema hash
--]]

local function compile(text: string): (Parser.File, Diagnostics.Diagnostics, number)
	local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(Source.new("Test.volt", text))
	local file: Parser.File = Parser.parse(Lexer.scan(diagnostics.source, diagnostics), diagnostics)

	Resolve.file(file, diagnostics)
	return file, diagnostics, Analyse.file(file, diagnostics)
end

local function report(text: string): string
	local diagnostics: Diagnostics.Diagnostics = select(2, compile(text))
	return diagnostics:render()
end

describe("Analyse", function ()
	describe("sizes", function ()
		for _, row: { any } in SIZES do
			test(row[1], function ()
				local file: Parser.File, diagnostics = compile(schema(`{NAMED}type T = {row[1]}`))
				local size: Analyse.Size = Analyse.size((file.declarations[3] :: any).type)

				expect(diagnostics:render()).is("")
				expect(size.min).is(row[2])
				expect(size.max).is(row[3])
				expect(size.bits).is(row[4])
				expect(size.slots).is(row[5])
			end)
		end
	end)

	test("assigns ids in declaration order, per direction, depth first through namespaces", function ()
		local text: string = schema(
			"event A { from: Client, type: Reliable, call: Polling }\nevent B { from: Server, type: Reliable, call: Polling }\nevent C { from: Both, type: Reliable, call: Polling }\nnamespace N { function F {} event D { from: Client, type: Reliable, call: Polling } }\nevent E { from: Server, type: Reliable, call: Polling }"
		)
		local file: Parser.File, diagnostics = compile(text)
		local a: any, b: any, c: any, n: any, e: any = table.unpack(file.declarations)
		local f: any, d: any = table.unpack(n.declarations)

		expect(diagnostics:render()).is("")
		expect(a.toServer).is(1)
		expect(a.toClient).is(nil)
		expect(b.toClient).is(1)
		expect(b.toServer).is(nil)
		expect(c.toServer).is(2)
		expect(c.toClient).is(2)
		expect(f.toServer).is(3)
		expect(f.toClient).is(3)
		expect(d.toServer).is(4)
		expect(e.toClient).is(4)
	end)

	describe("diagnostics", function ()
		test(
			"V3007 reports the wrong number or kind of type arguments, and a class on a type that takes none",
			function ()
				local text: string = schema(
					"type A = Vector3<f32, f32>\ntype B = CFrame<f32>\ntype C = Vector2<string>\ntype D = Color3(Part)\ntype E = Color3<u8>"
				)
				local first: string =
					rendered(text, "Vector3<f32, f32>", "error V3007: Vector3 takes one numeric type argument, got 2")
				local second: string =
					rendered(text, "CFrame<f32>", "error V3007: CFrame takes two numeric type arguments, got 1")
				local third: string = rendered(
					text,
					"string",
					"error V3007: Vector2's type argument must be a numeric primitive, got string"
				)
				local fourth: string = rendered(text, "Color3(Part)", "error V3007: Color3 takes no class")
				local fifth: string = rendered(text, "Color3<u8>", "error V3007: Color3 takes no type arguments, got 1")

				expect(report(text)).is(`{first}\n\n{second}\n\n{third}\n\n{fourth}\n\n{fifth}`)
			end
		)

		test("V3008 reports a map key or set element the reader cannot compare", function ()
			local text: string =
				schema("type A = { [struct { x: u8 }]: u8 }\ntype B = set<u8?>\ntype C = { [unknown]: u8 }")
			local wanted: string = "must be a primitive, string, enum or Roblox type"
			local first: string =
				rendered(text, "struct { x: u8 }", `error V3008: a map key {wanted}, got struct \{ x: u8 }`)
			local second: string = rendered(text, "u8?", `error V3008: a set element {wanted}, got u8?`)
			local third: string = rendered(text, "unknown", `error V3008: a map key {wanted}, got unknown`)

			expect(report(text)).is(`{first}\n\n{second}\n\n{third}`)
		end)

		test("V3009 reports union members the writer cannot tell apart, and lets unit enums flatten", function ()
			local text: string = schema(
				"type A = u8 | f32\ntype B = string | enum { X }\ntype C = struct { a: u8 } | struct { b: u8 }\ntype D = Instance | Instance(Part)\ntype Opt = u8?\ntype E = Opt | string\ntype F = unknown | u8\ntype G = enum { X } | enum { Y }\ntype H = u8[] | { [u8]: u8 }"
			)
			local first: string =
				rendered(text, "f32", "error V3009: union members u8 and f32 are both numbers at runtime")
			local second: string = rendered(
				text,
				"enum { X }",
				"error V3009: union members string and enum { X } are both strings at runtime"
			)
			local third: string = rendered(
				text,
				"struct { b: u8 }",
				"error V3009: union members struct { a: u8 } and struct { b: u8 } are both tables with named fields at runtime"
			)
			local fourth: string = rendered(
				text,
				"Instance(Part)",
				"error V3009: union members Instance and Instance(Part) are both instances at runtime"
			)
			local fifth: string = rendered(
				text,
				"Opt",
				"error V3009: union member Opt is optional; make the whole union optional instead",
				2
			)
			local sixth: string =
				rendered(text, "unknown", "error V3009: unknown cannot be a union member; it already takes any value")
			local seventh: string = rendered(
				text,
				"{ [u8]: u8 }",
				"error V3009: union members u8[] and { [u8]: u8 } are both arrays or maps at runtime"
			)

			expect(report(text)).is(`{first}\n\n{second}\n\n{third}\n\n{fourth}\n\n{fifth}\n\n{sixth}\n\n{seventh}`)
		end)

		test("V3010 refuses an unreliable event whose largest message, id included, is over the budget", function ()
			local text: string = schema(
				"option unreliableBudget = 4\nnamespace N { event Big { from: Client, type: Unreliable, call: Polling, data: (a: u8, b: u16, c: u8) } }\nevent Fits { from: Client, type: Unreliable, call: Polling, data: (a: u8, b: u16) }"
			)
			local unbounded: string =
				schema("event Big { from: Client, type: Unreliable, call: Polling, data: string }")

			expect(report(text)).is(
				rendered(text, "type", "error V3010: event N.Big can reach 5 bytes, over the unreliable budget of 4")
			)
			expect(report(unbounded)).is(
				rendered(
					unbounded,
					"type",
					"error V3010: event Big can reach 65538 bytes, over the unreliable budget of 900"
				)
			)
		end)

		test("V3011 reports a range a primitive cannot take", function ()
			local text: string = schema(
				"type A = q16\ntype B = q8(0..)\ntype C = boolean(0..1)\ntype D = u8(0..256)\ntype E = i8(-129..0)\ntype F = u16(1.5..3)\ntype G = u8(5..2)\ntype H = string(-1..4)\ntype I = u8[3..1]\ntype J = f32(0.5..1.5)\ntype K = u64(0..18446744073709551615)"
			)
			local expected: { string } = {
				rendered(text, "q16", "error V3011: q16 needs a range with both ends, such as q16(0..1)"),
				rendered(text, "0..", "error V3011: q8 needs a range with both ends, such as q8(0..1)"),
				rendered(text, "0..1", "error V3011: boolean takes no range"),
				rendered(text, "0..256", "error V3011: u8's range is outside its bounds 0..255"),
				rendered(text, "-129..0", "error V3011: i8's range is outside its bounds -128..127"),
				rendered(text, "1.5..3", "error V3011: u16's range has a fractional end, 1.5"),
				rendered(text, "5..2", "error V3011: a range's minimum is above its maximum"),
				rendered(text, "-1..4", "error V3011: a length must be a whole number of at least 0, got -1"),
				rendered(text, "3..1", "error V3011: a range's minimum is above its maximum"),
				rendered(
					text,
					"0..18446744073709551615",
					"error V3011: u64's range is outside its bounds 0..9007199254740992"
				),
			}

			expect(report(text)).is(table.concat(expected, "\n\n"))
		end)
	end)

	describe("hash", function ()
		test("is FNV-1a 32", function ()
			expect(Analyse.hash("")).is(0x811C9DC5)
			expect(Analyse.hash("a")).is(0xE40C292C)
			expect(Analyse.hash("foobar")).is(0xBF9CF968)
		end)

		test("ignores comments and whitespace and changes with the wire", function ()
			local commented: string = EXAMPLE:gsub("\n", " -- a comment\n"):gsub("\t", "    ")
			local edited: string = EXAMPLE:gsub("u16%(1%.%.999%)", "u16")
			local _, diagnostics, hash = compile(EXAMPLE)

			expect(diagnostics:render()).is("")
			expect(select(3, compile(commented))).is(hash)
			expect(select(3, compile(edited))).never_is(hash)
		end)
	end)

	test("prints the canonical form with resolved paths, ids and sizes, namespaces indented", function ()
		local file: Parser.File = compile(EXAMPLE)
		local printed: string = Analyse.print(file)
		local lines: { string } = {
			"option scope = Test",
			"type Stack = struct { item: string(1..32), quantity: u16(1..999), properties: unknown? } -- 4..35 bytes, 1 flag bit, 2 references",
			"event Input { from: Client, type: Unreliable, call: SingleSync, data: (dir: u8(0..8), jump: boolean, look: q16(-3.2..3.2)), queue: 64, rate: 120 } -- to server 1, payload 4 bytes",
			"namespace Inventory {\n\tevent Patch { from: Server, type: Reliable, call: SingleAsync, data: struct { version: u32, set: { [u8]: Stack }(0..64), cleared: u8[0..64] }, queue: 64, rate: 120 } -- to client 1, payload 6..2438 bytes",
			"\tfunction Transfer { data: (source: Reference, destination: Reference, slot: u8, quantity: u16), return: (ok: boolean, reason: string(0..128)?), yield: Promise, timeout: 5, rate: 60 } -- to server 2, to client 2, data 7..133 bytes, return 1..130 bytes\n}",
		}

		for _, line: string in lines do
			expect(printed:find(line, 1, true) ~= nil).is(true)
		end
	end)
end)
