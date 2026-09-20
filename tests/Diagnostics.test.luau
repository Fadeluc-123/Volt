--[[
    Proves a diagnostic renders as the location line and underlined excerpt
    the design shows, that the underline stays aligned past tabs and stops
    at the end of the line, and that warnings never count as errors
--]]

--!strict
local Suite = require("./Suite")
local Diagnostics = require("@volt/Compiler/Diagnostics")
local Source = require("@volt/Compiler/Source")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

describe("Diagnostics", function ()
	test("renders a location line and an underlined excerpt", function ()
		local source: Source.Source = Source.new("Game.volt", "option a = 1\nevent Input {\n    form: Client,\n}\n")
		local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(source)

		diagnostics:error(
			"V2004",
			`unknown key "form" in event Input (did you mean "from"?)`,
			{ start = 32, finish = 35 }
		)

		local location: string = `Game.volt:3:5: error V2004: unknown key "form" in event Input (did you mean "from"?)`
		local excerpt: string = "    3 |     form: Client,"
		local underline: string = "      |     ^^^^"

		expect(diagnostics:render()).is(`{location}\n{excerpt}\n{underline}`)
		expect(diagnostics.errors).is(1)
	end)

	test("keeps the underline aligned past tabs and clips it at the line end", function ()
		local source: Source.Source = Source.new("Test.volt", "\tevent Input {\nx")
		local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(source)

		diagnostics:warn("V0000", "spans the line", { start = 2, finish = 20 })

		local location: string = "Test.volt:1:2: warning V0000: spans the line"
		local excerpt: string = "    1 | \tevent Input {"
		local underline: string = "      | \t^^^^^^^^^^^^^"

		expect(diagnostics:render()).is(`{location}\n{excerpt}\n{underline}`)
		expect(diagnostics.errors).is(0)
	end)

	test("separates entries with a blank line and counts only errors", function ()
		local source: Source.Source = Source.new("T.volt", "a\nb")
		local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(source)

		diagnostics:warn("V0001", "first", { start = 1, finish = 1 })
		diagnostics:error("V0002", "second", { start = 3, finish = 3 })

		local first: string = "T.volt:1:1: warning V0001: first\n    1 | a\n      | ^"
		local second: string = "T.volt:2:1: error V0002: second\n    2 | b\n      | ^"

		expect(diagnostics:render()).is(`{first}\n\n{second}`)
		expect(diagnostics.errors).is(1)
	end)
end)
