--[[
    The volt command: reads a schema from one file or a folder of them and
    any further files, runs it through every stage, prints each diagnostic
    and exits non-zero on an error, then writes the modules and shards
    where the options file asks, or with --check compares them with the
    files there. --watch compiles again as the schema changes, --ast prints
    the canonical form and --quiet drops the one-line summary
--]]

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

-- An init file stands for its folder, so its siblings are reached through the folder's name
local Analyse = require("./Compiler/Analyse")
local Diagnostics = require("./Compiler/Diagnostics")
local Parser = require("./Compiler/Parser")
local Pieces = require("./Compiler/Targets/Pieces")
local Print = require("./Compiler/Analyse/Print")
local Resolve = require("./Compiler/Resolve")
local Schema = require("./Compiler/Config/Types/Schema")
local Source = require("./Compiler/Source")
local Targets = require("./Compiler/Targets")
local TargetsTypes = require("./Compiler/Config/Types/Targets")
local Watch = require("./Compiler/Watch")

type Extra = TargetsTypes.Extra
type Module = { output: string?, text: string }

local USAGE: string = "usage: volt <schema.volt | folder> [<file.volt> ...] [--check | --watch] [--ast] [--quiet]"

local flags: { [string]: boolean } = {}
local paths: { string } = {}

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

-- Line endings aside, so a checkout that turned them into CRLF still matches
local function normalised(text: string): string
	return (text:gsub("\r\n", "\n"))
end

--[[
    The shards past the count each side now has, from the next number up
    while such a file exists, so a schema that shrinks or stops sharding
    leaves none behind: a write removes them all, and --check reports the
    first of each side as no longer generated. Returns how many it reported
--]]

local function leftovers(schema: string, directory: string, options: Schema.Options, extra: { Extra }): number
	local generated: { [string]: boolean } = {}
	local stale: number = 0

	for _, piece: Extra in extra do
		generated[piece.output] = true
	end

	for _, output: string in { options.clientOutput :: string, options.serverOutput :: string } do
		local index: number = 1

		while generated[Pieces.shardPath(output, index)] do
			index += 1
		end

		local leftover: string = Pieces.shardPath(output, index)

		if flags.check and fs.isFile(`{directory}{leftover}`) then
			stale += 1
			stdio.ewrite(`{schema}: {leftover} is no longer generated\n`)
		end

		while not flags.check and fs.isFile(`{directory}{leftover}`) do
			fs.removeFile(`{directory}{leftover}`)
			index += 1
			leftover = Pieces.shardPath(output, index)
		end
	end

	return stale
end

--[[
    One compile of the schema the paths name, as the one-shot command and
    each compile of watch mode run it: diagnostics on stderr, the canonical
    form with --ast, every file written, or with --check compared, and the
    summary unless --quiet. Returns the code the command exits with
--]]

local function compile(): number
	local files: { string } = Watch.files(paths)

	-- Under watch mode a file the command reads, or every file in its folder, may go missing until the next change
	if #files == 0 then
		stdio.ewrite(`volt: {paths[1]} holds no schema file\n`)
		return 1
	end

	for _, path: string in files do
		if not fs.isFile(path) then
			stdio.ewrite(`volt: {path} is missing\n`)
			return 1
		end
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
	local extra: { Extra } = {}

	-- The generator walks a tree in which every lookup succeeds, so it runs only when the stages before it are clean
	if diagnostics.errors == 0 then
		client, server, types, extra = Targets.modules(file, diagnostics, hash)
	end

	if #diagnostics.list > 0 then
		stdio.ewrite(`{diagnostics:render()}\n`)
	end

	if flags.ast then
		print(Print.file(file))
	end

	if diagnostics.errors > 0 then
		return 1
	end

	local options: Schema.Options = file.options
	local directory: string = source.path:match("^(.*[/\\])") or "" -- Output paths are relative to the options file
	local stale: number = 0

	-- Each module beside the option that says where it goes, the types only where the schema asks, then every extra file
	local modules: { Module } = {
		{ output = options.clientOutput, text = client },
		{ output = options.serverOutput, text = server },
		{ output = options.typesOutput, text = types },
	}

	for _, piece: Extra in extra do
		table.insert(modules, { output = piece.output, text = piece.text })
	end

	for _, module: Module in modules do
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

	stale += leftovers(source.path, directory, options, extra)

	if stale > 0 then
		return 1
	end

	if not flags.quiet then
		print(`{source.path}: ok, schema hash {string.format("0x%08X", hash)}`)
	end

	return 0
end

if #paths == 0 or flags.check and flags.watch then
	usage()
end

-- A folder must hold a schema file directly inside it, and each further file must be one
if fs.isDir(paths[1]) and #Watch.files({ paths[1] }) == 0 then
	usage()
end

for index: number = 2, #paths do
	if not Watch.isSchema(paths[index]) then
		usage()
	end
end

if flags.watch then
	Watch.run(paths, compile)
else
	process.exit(compile())
end
