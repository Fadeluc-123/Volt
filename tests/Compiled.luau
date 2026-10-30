--[[
    A schema text through every stage before the generator, whatever it
    reports, so a test can read its tree, its diagnostics and its hash
    without the generator ever walking a tree that failed
--]]

--!strict
local Analyse = require("@volt/Compiler/Analyse")
local Diagnostics = require("@volt/Compiler/Diagnostics")
local Lexer = require("@volt/Compiler/Lexer")
local Parser = require("@volt/Compiler/Parser")
local Resolve = require("@volt/Compiler/Resolve")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Source = require("@volt/Compiler/Source")

return function (text: string): (Schema.File, Diagnostics.Diagnostics, number)
	local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(Source.new("Test.volt", text))
	local file: Schema.File = Parser.parse(Lexer.scan(diagnostics.source, diagnostics), diagnostics)

	Resolve.file(file, diagnostics)

	return file, diagnostics, Analyse.file(file, diagnostics)
end
