--[[
    Proves every type form and declaration form parses into the node the
    design describes by printing the tree back to source, that nodes carry
    their spans and values, that each V2xxx diagnostic is reported where it
    happens, and that a parse resumes at the next declaration after an
    error so one run reports every problem in the file
--]]

--!strict
local fs = require("@lune/fs")

local Suite = require("./Suite")
local Diagnostics = require("@volt/Compiler/Diagnostics")
local Lexer = require("@volt/Compiler/Lexer")
local Parser = require("@volt/Compiler/Parser")
local Source = require("@volt/Compiler/Source")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Declaration = Parser.Declaration
type Type = Parser.Type

local EVENT_KEYS: { string } = { "from", "type", "call", "data", "queue", "rate" }
local FUNCTION_KEYS: { string } = { "data", "return", "yield", "timeout", "rate" }
local EXAMPLE: string = fs.readFile("tests/Schemas/Example.volt") -- The design's complete example

-- Every type form, each of which must print back exactly as written
local TYPES: { string } = {
	"u8",
	"u8(0..8)",
	"i16(-100..100)",
	"f32(0..1)",
	"q16(-3.2..3.2)",
	"string(0..64)",
	"string(8)",
	"buffer(0..1024)",
	"u32(0..)",
	"u32(..8)",
	"boolean",
	"unknown",
	"Vector3",
	"Vector3<q16(-1024..1024)>",
	"Vector2<f16>",
	"CFrame<f32, f16>",
	"AlignedCFrame<i16>",
	"Color3",
	"BrickColor",
	"DateTime",
	"DateTimeMillis",
	"Instance",
	"Instance(Part)",
	"StreamedInstance(Model)",
	"Enum.Material",
	"EnumItem",
	"Stack",
	"Inventory.Stack",
	"u8?",
	"Stack[]",
	"Stack[0..256]",
	"u8[16]",
	"u8[0..4][2]",
	"{ [u8]: Stack }",
	"{ [string(1..32)]: u8 }(0..64)",
	"set<u8>",
	"set<Stack>(0..64)",
	"struct { a: u8, b: string(1..4)? }",
	"enum { A, B }",
	`enum "kind" \{ A \{ x: u8 }, B }`,
	"u8 | string",
	"u8 | string?",
	"u8[] | Vector3?",
}

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
	},
}

--[[
    Lexes and parses a fragment, returning the file and its diagnostics
--]]

local function parse(text: string): (Parser.File, Diagnostics.Diagnostics)
	local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(Source.new("Test.volt", text))
	local file: Parser.File = Parser.parse(Lexer.scan(diagnostics.source, diagnostics), diagnostics)

	return file, diagnostics
end

local function report(text: string): string
	local diagnostics = select(2, parse(text))
	return diagnostics:render()
end

--[[
    The three lines a diagnostic renders as when it points at the nth
    occurrence of a needle in the text
--]]

local function rendered(text: string, needle: string, message: string, nth: number?): string
	local source: Source.Source = Source.new("Test.volt", text)
	local start: number = 0

	for _ = 1, nth or 1 do
		start = source.text:find(needle, start + 1, true) :: number
	end

	local line: number, column: number = source:position(start)
	local excerpt: string = source:lineText(line)
	local lead: string = excerpt:sub(1, column - 1):gsub("[^\t]", " ")
	local carets: string = string.rep("^", #needle)

	return `Test.volt:{line}:{column}: {message}\n{string.format("%5d | %s", line, excerpt)}\n      | {lead}{carets}`
end

local function formatRange(range: Parser.Range?, open: string, close: string): string
	if not range then
		return ""
	end

	local min: string = range.min and tostring(range.min) or ""
	local max: string = range.max and tostring(range.max) or ""

	return range.min == range.max and `{open}{min}{close}` or `{open}{min}..{max}{close}`
end

local formatFields: ({ Parser.Field }) -> string

--[[
    Prints a type node back as schema source
--]]

local function formatType(node: Type): string
	if node.kind == "primitive" then
		return `{node.name}{formatRange(node.range, "(", ")")}`
	elseif node.kind == "roblox" then
		local generics: { string } = {}
		if node.generics then
			for _, generic: Type in node.generics do
				table.insert(generics, formatType(generic))
			end
		end

		local item: string = node.item and `.{node.item}` or ""
		local class: string = node.class and `({node.class})` or ""
		local arguments: string = #generics > 0 and `<{table.concat(generics, ", ")}>` or ""

		return `{node.name}{item}{class}{arguments}`
	elseif node.kind == "struct" then
		return `struct \{ {formatFields(node.fields)} }`
	elseif node.kind == "enum" then
		local variants: { string } = {}
		for _, variant: Parser.Variant in node.variants do
			table.insert(
				variants,
				variant.fields and `{variant.name} \{ {formatFields(variant.fields)} }` or variant.name
			)
		end

		local tag: string = node.tag and `"{node.tag}" ` or ""
		return `enum {tag}\{ {table.concat(variants, ", ")} }`
	elseif node.kind == "set" then
		return `set<{formatType(node.element)}>{formatRange(node.range, "(", ")")}`
	elseif node.kind == "map" then
		return `\{ [{formatType(node.key)}]: {formatType(node.value)} }{formatRange(node.range, "(", ")")}`
	elseif node.kind == "array" then
		return `{formatType(node.element)}{node.range and formatRange(node.range, "[", "]") or "[]"}`
	elseif node.kind == "optional" then
		return `{formatType(node.inner)}?`
	elseif node.kind == "union" then
		local members: { string } = {}
		for _, member: Type in node.members do
			table.insert(members, formatType(member))
		end

		return table.concat(members, " | ")
	end

	return node.name
end

function formatFields(fields: { Parser.Field }): string
	local parts: { string } = {}
	for _, field: Parser.Field in fields do
		table.insert(parts, `{field.name}: {formatType(field.type)}`)
	end
	return table.concat(parts, ", ")
end

--[[
    Prints a record value: a parameter pack or a type
--]]

local function formatValue(value: any): string
	if typeof(value) ~= "table" then
		return tostring(value)
	end
	return value.kind == "pack" and `({formatFields(value.parameters)})` or formatType(value)
end

--[[
    Prints a declaration back as schema source, with record keys in shape
    order and struct and enum declarations in their type form
--]]

local function formatDeclaration(node: Declaration): string
	if node.kind == "type" then
		return `{node.export and "export " or ""}type {node.name} = {formatType(node.type)}`
	elseif node.kind == "namespace" then
		local inner: { string } = {}
		for _, declaration: Declaration in node.declarations do
			table.insert(inner, formatDeclaration(declaration))
		end

		return `namespace {node.name} \{ {table.concat(inner, " ")} }`
	end

	local entries: { string } = {}
	for _, key: string in node.kind == "event" and EVENT_KEYS or FUNCTION_KEYS do
		local value: any = (node :: any)[key]

		if value ~= nil then
			table.insert(entries, `{key}: {formatValue(value)}`)
		end
	end

	return #entries == 0 and `{node.kind} {node.name} \{}`
		or `{node.kind} {node.name} \{ {table.concat(entries, ", ")} }`
end

--[[
    Parses one declaration that must be clean and prints it back
--]]

local function roundTrip(text: string): string
	local file: Parser.File, diagnostics = parse(text)

	expect(diagnostics:render()).is("")
	expect(#file.declarations).is(1)

	return formatDeclaration(file.declarations[1])
end

describe("Parser", function ()
	describe("types", function ()
		for _, source: string in TYPES do
			test(source, function ()
				expect(roundTrip(`type T = {source}`)).is(`type T = {source}`)
			end)
		end
	end)

	describe("declarations", function ()
		for _, pair: { string } in DECLARATIONS do
			test(pair[1], function ()
				expect(roundTrip(pair[1])).is(pair[2] or pair[1])
			end)
		end
	end)

	test("options carry each value kind and a span per key", function ()
		local text: string =
			`option clientOutput = "../Net.luau"\noption flush = 2\noption scope = Game\noption casing = pascal\noption writeValidation = false\noption rate = unlimited`
		local file: Parser.File, diagnostics = parse(text)
		local start: number?, finish: number? = text:find("flush", 1, true)

		expect(diagnostics:render()).is("")
		expect(file.options.clientOutput).is("../Net.luau")
		expect(file.options.flush).is(2)
		expect(file.options.scope).is("Game")
		expect(file.options.casing).is("pascal")
		expect(file.options.writeValidation).is(false)
		expect(file.options.rate).is("unlimited")
		expect(file.options.spans.flush.start).is(start)
		expect(file.options.spans.flush.finish).is(finish)
	end)

	test("ranges carry numbers, with a missing end nil and one number as both ends", function ()
		local file: Parser.File = parse("type A = q16(-3.2..3.2)\ntype B = u8(..8)\ntype C = string(8)")

		local function rangeOf(index: number): Parser.Range
			return (file.declarations[index] :: any).type.range
		end

		expect(rangeOf(1).min).is(-3.2)
		expect(rangeOf(1).max).is(3.2)
		expect(rangeOf(2).min).is(nil)
		expect(rangeOf(2).max).is(8)
		expect(rangeOf(3).min).is(8)
		expect(rangeOf(3).max).is(8)
	end)

	test("a declaration's span is its name, a type's is its whole expression, a key's is the key", function ()
		local text: string =
			"event Input { from: Client, type: Reliable, call: Polling, rate: 8 }\ntype Id = u8(0..8)[]"
		local file: Parser.File = parse(text)
		local event: any = file.declarations[1]
		local declaration: any = file.declarations[2]

		expect(event.start).is((text:find("Input", 1, true)))
		expect(event.finish).is(select(2, text:find("Input", 1, true)))
		expect(event.spans.rate.start).is((text:find("rate", 1, true)))
		expect(declaration.start).is((text:find("Id", 1, true)))
		expect(declaration.type.start).is((text:find("u8(0..8)[]", 1, true)))
		expect(declaration.type.finish).is(#text)
		expect(declaration.type.element.range.start).is((text:find("0..8", 1, true)))
		expect(declaration.type.element.range.finish).is((text:find("8)", 1, true)))
	end)

	test("the design's complete example parses without a diagnostic", function ()
		local file: Parser.File, diagnostics = parse(EXAMPLE)
		local namespace: any = file.declarations[6]

		expect(diagnostics:render()).is("")
		expect(file.options.yield).is("promise")
		expect(file.options.promise).is("ReplicatedStorage.Packages.Promise")
		expect(#file.declarations).is(6)
		expect(namespace.kind).is("namespace")
		expect(#namespace.declarations).is(2)
		expect(namespace.declarations[2]["return"].kind).is("pack")
	end)

	describe("diagnostics", function ()
		test("V2001 reports the token found where another was expected", function ()
			local text: string = "type A = 5\nevent Input { from Client }"
			local first: string = rendered(text, "5", `error V2001: expected a type, got "5"`)
			local second: string = rendered(text, "Client", `error V2001: expected ":", got "Client"`)

			expect(report(text)).is(`{first}\n\n{second}`)
		end)

		test("V2002 reports a duplicate key, field or variant and keeps the first", function ()
			local text: string =
				"event Input { from: Client, from: Server, type: Reliable, call: Polling }\nstruct S { x: u8, x: u8 }\nenum E { A, A }"
			local file: Parser.File = parse(text)
			local first: string = rendered(text, "from", `error V2002: duplicate key "from" in event Input`, 2)
			local second: string = rendered(text, "x", `error V2002: duplicate field "x"`, 2)
			local third: string = rendered(text, "A", `error V2002: duplicate variant "A"`, 2)

			expect(report(text)).is(`{first}\n\n{second}\n\n{third}`)
			expect((file.declarations[1] :: any).from).is("Client")
			expect(#(file.declarations[2] :: any).type.fields).is(1)
		end)

		test("V2003 reports an unknown key, skips its value and keeps parsing the record", function ()
			local text: string =
				"option foo = 1\noption flush = 2\nevent Input { form: Client, from: Client, type: Reliable, call: Polling }"
			local file: Parser.File = parse(text)
			local options: string =
				"clientOutput, serverOutput, typesOutput, runtime, scope, casing, writeValidation, manualReplication, flush, maxPacket, maxPacketsPerSecond, unreliableBudget, queue, rate, functionRate, timeout, yield, promise"
			local first: string =
				rendered(text, "foo", `error V2003: unknown key "foo" in the options; keys are {options}`)
			local second: string = rendered(
				text,
				"form",
				`error V2003: unknown key "form" in event Input; keys are from, type, call, data, queue, rate`
			)

			expect(report(text)).is(`{first}\n\n{second}`)
			expect(file.options.flush).is(2)
			expect((file.declarations[1] :: any).from).is("Client")
		end)

		test("V2004 reports every missing key at the record's name", function ()
			local text: string = "event Input { from: Client }"
			local first: string = rendered(text, "Input", `error V2004: missing key "type" in event Input`)
			local second: string = rendered(text, "Input", `error V2004: missing key "call" in event Input`)

			expect(report(text)).is(`{first}\n\n{second}`)
		end)

		test("V2005 reports a value of the wrong shape", function ()
			local text: string =
				`option flush = "2"\nevent Input \{ from: client, type: Reliable, call: Polling, rate: fast }`
			local first: string =
				rendered(text, `"2"`, `error V2005: expected a number for key "flush", got string "2"`)
			local second: string = rendered(
				text,
				"client",
				`error V2005: expected one of Client, Server, Both for key "from", got "client"`
			)

			expect(report(text)).is(`{first}\n\n{second}`)
			expect(report("event Input { from: Client, type: Reliable, call: Polling, rate: fast }")).is(
				rendered(
					"event Input { from: Client, type: Reliable, call: Polling, rate: fast }",
					"fast",
					`error V2005: expected a number or unlimited for key "rate", got "fast"`
				)
			)
		end)

		test("V2006 reports a reserved word used as a name and a tag that is not a name", function ()
			local text: string = `struct S \{ end: u8 }\nenum E "my kind" \{ A }`
			local first: string =
				rendered(text, "end", `error V2006: "end" is a Luau reserved word and cannot be a name`)
			local second: string = rendered(text, `"my kind"`, `error V2006: tag "my kind" is not a valid Luau name`)

			expect(report(text)).is(`{first}\n\n{second}`)
		end)

		test("V2007 reports fields on a variant of an enum with no tag", function ()
			local text: string = "enum Team { Red { x: u8 } }"

			expect(report(text)).is(
				rendered(text, "Red", `error V2007: variant "Red" has fields but the enum has no tag`)
			)
		end)

		test("V2008 names the phase 2 syntax it does not accept", function ()
			local text: string = `type Box<T> = T\nstruct S \{ ..Base }\ntype Switch = "on" | "off"`
			local first: string = rendered(text, "<", "error V2008: generic types are not supported in this version")
			local second: string = rendered(text, "..", "error V2008: struct spread is not supported in this version")
			local third: string = rendered(text, `"on"`, "error V2008: literal types are not supported in this version")

			expect(report(text)).is(`{first}\n\n{second}\n\n{third}`)
		end)

		test("V2009 reports an option after a declaration and still reads it", function ()
			local text: string = "type A = u8\noption flush = 2"
			local file: Parser.File = parse(text)

			expect(report(text)).is(
				rendered(text, "option", `error V2009: option "flush" comes after a declaration; options come first`)
			)
			expect(file.options.flush).is(2)
		end)
	end)

	describe("recovery", function ()
		test("resumes at the next declaration so every error is reported", function ()
			local text: string =
				"type A = |\nevent B { from: Client, type: Reliable, call: Polling }\ntype C = u8 |\ntype D = u8"
			local file: Parser.File, diagnostics = parse(text)

			expect(diagnostics.errors).is(2)
			expect(#file.declarations).is(2)
			expect(formatDeclaration(file.declarations[1])).is(
				"event B { from: Client, type: Reliable, call: Polling }"
			)
			expect(formatDeclaration(file.declarations[2])).is("type D = u8")
		end)

		test("resumes inside a namespace and still closes it", function ()
			local text: string = "namespace N { type A = , type B = u8 }\ntype C = u8"
			local file: Parser.File, diagnostics = parse(text)

			expect(diagnostics.errors).is(1)
			expect(formatDeclaration(file.declarations[1])).is("namespace N { type B = u8 }")
			expect(formatDeclaration(file.declarations[2])).is("type C = u8")
		end)

		test("a missing closing brace loses only its own declaration", function ()
			local text: string =
				"event A { from: Client, type: Reliable, call: Polling\nevent B { from: Client, type: Reliable, call: Polling }"
			local file: Parser.File, diagnostics = parse(text)

			expect(diagnostics.errors).is(1)
			expect(formatDeclaration(file.declarations[1])).is(
				"event B { from: Client, type: Reliable, call: Polling }"
			)
		end)
	end)
end)
