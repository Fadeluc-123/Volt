--[[
    The volt command: reads a schema, runs it through the lexer, parser,
    resolver and analyser, prints every diagnostic and exits non-zero on
    an error. --check writes nothing, --ast prints the resolved
    declarations and --quiet keeps the summary line off the output
--]]

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

-- An init file stands for its folder, so its siblings are reached through the folder's name
local Analyse = require("./Compiler/Analyse")
local Diagnostics = require("./Compiler/Diagnostics")
local Lexer = require("./Compiler/Lexer")
local Parser = require("./Compiler/Parser")
local Print = require("./Compiler/Analyse/Print")
local Resolve = require("./Compiler/Resolve")
local Schema = require("./Compiler/Config/Types/Schema")
local Source = require("./Compiler/Source")

local USAGE: string = "usage: volt <schema.volt> [--check] [--ast] [--quiet]"

local flags: { [string]: boolean } = {}
local path: string? = nil

for _, argument: string in process.args do
	if argument:sub(1, 2) == "--" then
		flags[argument:sub(3)] = true
	else
		path = argument
	end
end

if not path then
	stdio.ewrite(`{USAGE}\n`)
	process.exit(2)
end

local source: Source.Source = Source.new(path :: string, fs.readFile(path :: string))
local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(source)
local file: Schema.File = Parser.parse(Lexer.scan(source, diagnostics), diagnostics)

Resolve.file(file, diagnostics)

local hash: number = Analyse.file(file, diagnostics)

if #diagnostics.list > 0 then
	stdio.ewrite(`{diagnostics:render()}\n`)
end

if flags.ast then
	print(Print.file(file))
end

-- Whiteoak TODO: generate and write the three modules once the emitter exists; until then every run is a check
if diagnostics.errors > 0 then
	process.exit(1)
elseif not flags.quiet then
	print(`{source.path}: ok, schema hash {string.format("0x%08X", hash)}`)
end
