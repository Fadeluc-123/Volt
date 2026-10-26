--[[
    The volt command: reads a schema from one file or a folder of them and
    any further files, runs it through every stage, prints each diagnostic
    and exits non-zero on an error, then writes the modules where the
    options file asks, or with --check compares them with the files there.
    --ast prints the canonical form and --quiet drops the one-line summary
--]]

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

-- An init file stands for its folder, so its siblings are reached through the folder's name
local Analyse = require("./Compiler/Analyse")
local Diagnostics = require("./Compiler/Diagnostics")
local Parser = require("./Compiler/Parser")
local Print = require("./Compiler/Analyse/Print")
local Resolve = require("./Compiler/Resolve")
local Schema = require("./Compiler/Config/Types/Schema")
local Source = require("./Compiler/Source")
local Targets = require("./Compiler/Targets")

local USAGE: string = "usage: volt <schema.volt | folder> [<file.volt> ...] [--check] [--ast] [--quiet]"
local EXTENSION: string = "%.volt$" -- What makes a file a schema file

local flags: { [string]: boolean } = {}
local paths: { string } = {}
local files: { string } = {}

for _, argument: string in process.args do
	if argument:sub(1, 2) == "--" then
		flags[argument:sub(3)] = true
	else
		table.insert(paths, argument)
	end
end

local function usage(): never
	stdio.ewrite(`{USAGE}\n`)
	return process.exit(2)
end

local function isSchema(path: string): boolean
	return path:match(EXTENSION) ~= nil and fs.isFile(path)
end

-- Line endings aside, so a checkout that turned them into CRLF still matches
local function normalised(text: string): string
	return (text:gsub("\r\n", "\n"))
end

if #paths == 0 then
	usage()
end

-- A folder takes every schema file directly inside it, by name, and none from its subfolders
if fs.isDir(paths[1]) then
	local folder: string = (paths[1]:gsub("[/\\]+$", ""))

	for _, name: string in fs.readDir(folder) do
		if isSchema(`{folder}/{name}`) then
			table.insert(files, `{folder}/{name}`)
		end
	end

	table.sort(files)

	if #files == 0 then
		usage()
	end
else
	table.insert(files, paths[1])
end

for index: number = 2, #paths do
	if not isSchema(paths[index]) then
		usage()
	end

	table.insert(files, paths[index])
end

local source: Source.Source = Source.new(files[1], fs.readFile(files[1]))

for index: number = 2, #files do
	source:add(files[index], fs.readFile(files[index]))
end

local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(source)
local file: Schema.File = Parser.schema(source, diagnostics)

Resolve.file(file, diagnostics)

local hash: number = Analyse.file(file, diagnostics)
local client: string, server: string, types: string = "", "", ""

-- The generator walks a tree in which every lookup succeeds, so it runs only when the stages before it are clean
if diagnostics.errors == 0 then
	client, server, types = Targets.modules(file, diagnostics, hash)
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

local options: Schema.Options = file.options
local directory: string = source.path:match("^(.*[/\\])") or "" -- Output paths are relative to the options file
local stale: number = 0

-- Each module beside the option that says where it goes; the types go only where the schema asks
local modules: { { output: string?, text: string } } = {
	{ output = options.clientOutput, text = client },
	{ output = options.serverOutput, text = server },
	{ output = options.typesOutput, text = types },
}

for _, module: { output: string?, text: string } in modules do
	local output: string? = module.output
	if output == nil then
		continue
	end

	local target: string = `{directory}{output}`

	if not flags.check then
		fs.writeFile(target, module.text)
	elseif not fs.isFile(target) then
		stale += 1
		stdio.ewrite(`{source.path}: {output} is missing\n`)
	elseif normalised(fs.readFile(target)) ~= normalised(module.text) then
		stale += 1
		stdio.ewrite(`{source.path}: {output} is out of date\n`)
	end
end

if stale > 0 then
	process.exit(1)
end

if not flags.quiet then
	print(`{source.path}: ok, schema hash {string.format("0x%08X", hash)}`)
end
