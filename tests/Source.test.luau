--[[
    Proves a byte offset renders as the right line and column and that a
    line is excerpted without its line ending, on both line-ending styles
--]]

--!strict
local Suite = require("./Suite")
local Source = require("@volt/Compiler/Source")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

describe("Source", function ()
	local source: Source.Source = Source.new("Game.volt", "option a = 1\n\tevent B {}\r\nend")

	test("renders offsets as line and column", function ()
		local function at(offset: number): string
			local line: number, column: number = source:position(offset)
			return `{line}:{column}`
		end

		expect(at(1)).is("1:1")
		expect(at(15)).is("2:2")
		expect(at(29)).is("3:3")
		expect(at(30)).is("3:4")
	end)

	test("excerpts a line without its ending", function ()
		expect(source:lineText(1)).is("option a = 1")
		expect(source:lineText(2)).is("\tevent B {}")
		expect(source:lineText(3)).is("end")
	end)
end)
