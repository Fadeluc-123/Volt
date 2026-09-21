--[[
    The volt command: reads a schema, runs it through the lexer, parser,
    resolver, analyser and generator, prints every diagnostic, exits
    non-zero on an error and otherwise writes the client and server
    modules beside the schema. --check writes nothing, --ast prints the
    resolved declarations and --quiet keeps the summary line off
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
local Targets = require("./Compiler/Targets")

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
local client: string, server: string = "", ""

-- The generator walks a tree in which every lookup succeeds, so it runs only when the stages before it are clean
if diagnostics.errors == 0 then
	client, server = Targets.modules(file, diagnostics, hash)
end

if #diagnostics.list > 0 then
	stdio.ewrite(`{diagnostics:render()}\n`)
end

if flags.ast then
	print(Print.file(file))
end

if diagnostics.errors > 0 then
	process.exit(1)
end

-- Whiteoak TODO: the types module is written here once it is generated
if not flags.check then
	local directory: string = (path :: string):match("^(.*[/\\])") or ""

	fs.writeFile(`{directory}{file.options.clientOutput}`, client)
	fs.writeFile(`{directory}{file.options.serverOutput}`, server)
end

if not flags.quiet then
	print(`{source.path}: ok, schema hash {string.format("0x%08X", hash)}`)
end
