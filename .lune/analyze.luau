--[[
    Runs luau-lsp analyze over the source, tests and Lune scripts under the
    new checker, with the Roblox definitions the runtime's transport needs,
    fetched once at the pinned version into Definitions/, and over the
    modules, shards and inspector every test schema and the folder form
    compile to, as a game sees them, under the old checker and the new
--]]

--!strict
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

local Generated = require("../tests/Generated")
local Analyse = require("@volt/Compiler/Analyse")
local Diagnostics = require("@volt/Compiler/Diagnostics")
local Parser = require("@volt/Compiler/Parser")
local Resolve = require("@volt/Compiler/Resolve")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Source = require("@volt/Compiler/Source")
local Targets = require("@volt/Compiler/Targets")
local TargetsTypes = require("@volt/Compiler/Config/Types/Targets")

type Extra = TargetsTypes.Extra

local VERSION: string = "1.70.0" -- The luau-lsp pinned in rokit.toml, whose definitions match its analyzer
local URL: string = `https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/{VERSION}/scripts/globalTypes.d.luau`
local FOLDER: string = "Definitions"
local PATH: string = `{FOLDER}/globalTypes.d.luau`
local MODULES: string = `{FOLDER}/Modules` -- The modules of every test schema as a game requires them, written here
local CODE: { string } = { "src", "tests", ".lune" } -- Volt's own code
local SCHEMAS: string = "tests/Schemas"
local SPLIT: string = "Split" -- The command test's folder form, whose modules are written under its name
local ARENA: string = `{SCHEMAS}/{SPLIT}/arena/Schemas` -- A mode's folder, which a game compiles as one schema
local GAME: string = `{SCHEMAS}/{SPLIT}/game/Schemas` -- The game's own folder, two of whose files the mode reuses
local REUSED: { string } = { `{GAME}/Types.volt`, `{GAME}/Combat.volt` } -- After the folder's own, in this order
local INSPECTOR: string = "option inspectorOutput" -- What a schema asks for its packet inspector with
local GOLDENS: string = "tests/Golden/**" -- The goldens themselves require a package no sourcemap resolves here
local VENDORED: string = "tests/tiniest/**" -- Vendored, so never edited to suit a checker
local SOLVER: string = "--flag:LuauSolverV2=true" -- The new checker, which Volt's code and a game's own gate run
local REPORTED: string = `^{MODULES}/.-%(%d+,%d+%): ` -- Any line about a module, an error or a lint alike

--[[
    A module's requires as this repository resolves them: the runtime
    through the tests' alias, the promise as its stand-in, and a shard
    under its schema's name, as write puts it
--]]

local function rewritten(name: string, text: string): string
	return (
		text:gsub('local ReplicatedStorage = game:GetService%("ReplicatedStorage"%)\n', "")
			:gsub("require%(ReplicatedStorage%.Packages%.Volt%)", 'require("@volt")')
			:gsub("require%(ReplicatedStorage%.Packages%.Promise%)", 'require("../../tests/Promise")')
			:gsub(`require%("%./([%w_]+)"%)`, `require("./{name}_%1")`)
	)
end

--[[
    Writes a schema's modules under its name: the client's and the
    server's, then each shard beside them, all with their requires
    rewritten, and the types module and the inspector, which requires
    nothing and finds its remotes through the service, as they are
--]]

local function write(name: string, client: string, server: string, types: string, extra: { Extra })
	fs.writeFile(`{MODULES}/{name}_Client.luau`, rewritten(name, client))
	fs.writeFile(`{MODULES}/{name}_Server.luau`, rewritten(name, server))
	fs.writeFile(`{MODULES}/{name}_Types.luau`, types)

	for _, file: Extra in extra do
		local base: string = file.output:match("[^/\\]+$") or file.output
		local requires: boolean = file.text:find("require(", 1, true) ~= nil

		fs.writeFile(`{MODULES}/{name}_{base}`, requires and rewritten(name, file.text) or file.text)
	end
end

--[[
    Compiles the mode's folder and the game's files it reuses as one
    schema, as the volt command does: the folder's schema files by name,
    then the further files in order. Returns the client's, the server's
    and the types module
--]]

local function compileFolder(): (string, string, string, { Extra })
	local paths: { string } = {}

	for _, name: string in fs.readDir(ARENA) do
		if name:match("%.volt$") then
			table.insert(paths, `{ARENA}/{name}`)
		end
	end

	table.sort(paths)
	table.move(REUSED, 1, #REUSED, #paths + 1, paths)

	local source: Source.Source = Source.new(paths[1], fs.readFile(paths[1]))

	for index: number = 2, #paths do
		source:add(paths[index], fs.readFile(paths[index]))
	end

	local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(source)
	local file: Schema.File = Parser.schema(source, diagnostics)

	Resolve.file(file, diagnostics)

	-- The generator walks a tree in which every lookup succeeds, so it runs only on a clean one
	local hash: number = Analyse.file(file, diagnostics)
	assert(diagnostics.errors == 0, diagnostics:render())

	local client: string, server: string, types: string, extra: { Extra } = Targets.modules(file, diagnostics, hash)
	assert(diagnostics.errors == 0, diagnostics:render())

	return client, server, types, extra
end

--[[
    Runs luau-lsp over the paths with the flags given, shows what it
    printed and says whether it passed: no error anywhere, and not one
    line, lint or error, about a generated module
--]]

local function analyze(flags: { string }, paths: { string }): boolean
	local arguments: { string } = { "analyze", `--definitions={PATH}` }

	table.move(flags, 1, #flags, #arguments + 1, arguments)
	table.move(paths, 1, #paths, #arguments + 1, arguments)

	local result = process.exec("luau-lsp", arguments)
	local printed: string = `{result.stdout}{result.stderr}`
	local clean: boolean = result.ok

	for line: string in printed:gmatch("[^\r\n]+") do
		if not line:match("^%[INFO%]") then
			print(line)
		end

		clean = clean and not line:match(REPORTED)
	end

	return clean
end

if not fs.isFile(PATH) then
	local response = net.request(URL)

	assert(response.ok, `Could not fetch {URL}: {response.statusCode} {response.statusMessage}`)
	fs.writeDir(FOLDER)
	fs.writeFile(PATH, response.body)
end

if fs.isDir(MODULES) then
	fs.removeDir(MODULES)
end

fs.writeDir(MODULES)

for _, name: string in fs.readDir(SCHEMAS) do
	local schema: string? = name:match("^(.+)%.volt$")

	if schema then
		local text: string = fs.readFile(`{SCHEMAS}/{name}`)

		-- Every schema's inspector, which changes none of its modules, so each type's reader is checked as one holds it
		if not text:find(INSPECTOR, 1, true) then
			text = `{INSPECTOR} = "Inspector.luau"\n{text}`
		end

		local client: string, server: string, types: string, extra: { Extra } = Generated.modules(schema, text)

		write(schema, client, server, types, extra)
	end
end

local client: string, server: string, types: string, extra: { Extra } = compileFolder()

write(SPLIT, client, server, types, extra)

-- Volt's own code is held to the new checker, the modules a game commits to both with the runtime they require
local code: boolean = analyze({ SOLVER, `--ignore={VENDORED}`, `--ignore={GOLDENS}` }, CODE)
local old: boolean = analyze({}, { MODULES })
local new: boolean = analyze({ SOLVER }, { MODULES })

process.exit((code and old and new) and 0 or 1)
