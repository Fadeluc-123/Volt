--[[
    Proves every token kind lexes with its value and span, that comments and
    whitespace vanish, that each V1xxx diagnostic is reported and the scan
    resumes on the next line, and that the design's complete example lexes
    without a diagnostic
--]]

--!strict
local fs = require("@lune/fs")

local Suite = require("./Suite")
local Diagnostics = require("@volt/Compiler/Diagnostics")
local Lexer = require("@volt/Compiler/Lexer")
local Source = require("@volt/Compiler/Source")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

local EXAMPLE: string = fs.readFile("tests/Schemas/Example.volt") -- The design's complete example

--[[
    Lexes a fragment and returns its tokens and diagnostics
--]]

local function scan(text: string): ({ Lexer.Token }, Diagnostics.Diagnostics)
	local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(Source.new("Test.volt", text))

	return Lexer.scan(diagnostics.source, diagnostics), diagnostics
end

--[[
    Lexes a fragment and flattens its tokens to one line of kind:value pairs
--]]

local function summary(text: string): string
	local tokens: { Lexer.Token } = scan(text)
	local parts: { string } = {}

	for _, token: Lexer.Token in tokens do
		table.insert(parts, token.kind == "eof" and "eof" or `{token.kind}:{token.value}`)
	end

	return table.concat(parts, " ")
end

--[[
    Asserts every word of a space-separated fragment lexes as one token of
    the given kind whose value is the word itself, followed by eof
--]]

local function expectEach(text: string, kind: string)
	local tokens: { Lexer.Token } = scan(text)
	local index: number = 0

	for word: string in text:gmatch("%S+") do
		index += 1
		expect(tokens[index].kind).is(kind)
		expect(tokens[index].value).is(word)
	end

	expect(tokens[index + 1].kind).is("eof")
end

describe("Lexer", function ()
	test("keywords", function ()
		expectEach("option export type struct enum namespace event function set", "keyword")
	end)

	test("primitives", function ()
		expectEach("u8 u16 u24 u32 u48 u64 i8 i16 i24 i32 i48 i64", "primitive")
		expectEach("f16 f32 f64 q8 q16 boolean string buffer unknown", "primitive")
	end)

	test("names", function ()
		expectEach("Input Vector3 Client _private a1 unlimited true", "name")
	end)

	test("numbers", function ()
		expectEach("120 -100 3.2 -3.2 0", "number")
	end)

	test("strings drop their quotes", function ()
		expect(summary(`"../src/Net.luau" ""`)).is("string:../src/Net.luau string: eof")
	end)

	test("ranges", function ()
		local expected: string =
			"primitive:u8 punctuation:( number:0 range:.. number:8 punctuation:) number:-3.2 range:.. number:3.2 eof"

		expectEach("..", "range")
		expect(summary("u8(0..8) -3.2..3.2")).is(expected)
	end)

	test("punctuation", function ()
		expectEach("{ } ( ) [ ] < > : , = | ? .", "punctuation")
	end)

	test("comments and whitespace produce no token", function ()
		expect(summary("-- a comment\n\tevent -- trailing\n")).is("keyword:event eof")
	end)

	test("tokens carry their byte span and eof sits past the end", function ()
		local tokens: { Lexer.Token } = scan("event  Input")

		expect(tokens[1].start).is(1)
		expect(tokens[1].finish).is(5)
		expect(tokens[2].start).is(8)
		expect(tokens[2].finish).is(12)
		expect(tokens[3].kind).is("eof")
		expect(tokens[3].start).is(13)
	end)

	test("V1001 reports an unterminated string and resumes on the next line", function ()
		local text: string = `option a = "oops\noption b = 1`
		local _, diagnostics = scan(text)

		local location: string = "Test.volt:1:12: error V1001: unterminated string"
		local excerpt: string = `    1 | option a = "oops`
		local underline: string = `      | {string.rep(" ", 11)}^^^^^`

		expect(diagnostics:render()).is(`{location}\n{excerpt}\n{underline}`)
		expect(summary(text)).is("keyword:option name:a punctuation:= keyword:option name:b punctuation:= number:1 eof")
	end)

	test("V1002 reports an unexpected character and resumes on the next line", function ()
		local text: string = "event @ Input\nevent B"
		local _, diagnostics = scan(text)

		local location: string = `Test.volt:1:7: error V1002: unexpected character "@"`
		local excerpt: string = "    1 | event @ Input"
		local underline: string = `      | {string.rep(" ", 6)}^`

		expect(diagnostics:render()).is(`{location}\n{excerpt}\n{underline}`)
		expect(summary(text)).is("keyword:event keyword:event name:B eof")
	end)

	test("the design's complete example lexes without a diagnostic", function ()
		local tokens: { Lexer.Token }, diagnostics = scan(EXAMPLE)

		expect(diagnostics.errors).is(0)
		expect(tokens[#tokens].kind).is("eof")
	end)
end)
