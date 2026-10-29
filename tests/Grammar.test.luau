--[[
    Proves the editor grammar in .vscode/volt-syntax names the words the
    compiler reads: its keyword, primitive, roblox and value rules each list
    exactly the lexer's keywords, the primitives, the Roblox types and the
    names a fixed option or message key value may take
--]]

--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Suite = require("./Suite")
local Lexer = require("@volt/Compiler/Lexer")
local Options = require("@volt/Compiler/Config/Options")
local Primitives = require("@volt/Compiler/Config/Primitives")
local Roblox = require("@volt/Compiler/Config/Roblox")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Spec = Options.Spec

local GRAMMAR: { [string]: { match: string } } =
	serde.decode("json", fs.readFile(".vscode/volt-syntax/syntaxes/volt.tmLanguage.json")).repository

--[[
    The words a rule lists inside its (?:...) group, sorted and joined, so
    an order the grammar keeps for reading never fails the comparison
--]]

local function listed(rule: string): string
	local words: { string } = (GRAMMAR[rule].match:match("%(%?:([%w_|]+)%)") or ""):split("|")
	table.sort(words)

	return table.concat(words, " ")
end

--[[
    The keys of a source's rows, sorted and joined the same way
--]]

local function keys(rows: { [string]: any }): string
	local words: { string } = {}
	for word: string in rows do
		table.insert(words, word)
	end
	table.sort(words)

	return table.concat(words, " ")
end

describe("Grammar", function ()
	test("the keyword rule lists the lexer's keywords", function ()
		expect(listed("keyword")).is(keys(Lexer.keywords))
	end)

	test("the primitive rule lists every primitive", function ()
		expect(listed("primitive")).is(keys(Primitives))
	end)

	test("the roblox rule lists every Roblox type", function ()
		expect(listed("roblox")).is(keys(Roblox))
	end)

	test("the value rule lists every name a values list allows", function ()
		local values: { [string]: boolean } = {}

		for _, shape: { Spec } in { Options.file, Options.event, Options["function"] } do
			for _, spec: Spec in shape do
				for _, value: string in spec.values or {} do
					values[value] = true
				end
			end
		end

		expect(listed("value")).is(keys(values))
	end)
end)
