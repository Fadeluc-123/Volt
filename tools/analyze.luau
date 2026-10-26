--[[
    Runs luau-lsp analyze over the source, tests and tools with the Roblox
    definitions the runtime's transport needs, fetched once at the pinned
    version into Definitions/, and over the modules every test schema
    compiles to, as a game sees them, under the old checker and the new
--]]

--!strict
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

local Generated = require("../tests/Generated")

local VERSION: string = "1.70.0" -- The luau-lsp pinned in rokit.toml, whose definitions match its analyzer
local URL: string = `https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/{VERSION}/scripts/globalTypes.d.luau`
local FOLDER: string = "Definitions"
local PATH: string = `{FOLDER}/globalTypes.d.luau`
local MODULES: string = `{FOLDER}/Modules` -- The modules of every test schema as a game requires them, written here
local SCHEMAS: string = "tests/Schemas"
local GOLDENS: string = "tests/Golden/**" -- The goldens themselves require a package no sourcemap resolves here
local SOLVER: string = "--flag:LuauSolverV2=true" -- The new checker, which a game's own gate may run
local REPORTED: string = `^{MODULES}/.-%(%d+,%d+%): ` -- Any line about a module, an error or a lint alike

-- A module's requires as this repository resolves them: the runtime through the tests' alias, the promise as its stand-in
local function rewritten(text: string): string
	return (
		text:gsub('local ReplicatedStorage = game:GetService%("ReplicatedStorage"%)\n', "")
			:gsub("require%(ReplicatedStorage%.Packages%.Volt%)", 'require("@volt")')
			:gsub("require%(ReplicatedStorage%.Packages%.Promise%)", 'require("../../tests/Promise")')
	)
end

--[[
    Runs luau-lsp over the paths with the flags given, shows what it
    printed and says whether it passed: no error anywhere, and not one
    line, lint or error, about a generated module
--]]

local function analyze(flags: { string }, paths: { string }): boolean
	local arguments: { string } = { "analyze", `--definitions={PATH}`, `--ignore={GOLDENS}` }

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
		local client: string, server: string, types: string = Generated.modules(schema, fs.readFile(`{SCHEMAS}/{name}`))

		fs.writeFile(`{MODULES}/{schema}_Client.luau`, rewritten(client))
		fs.writeFile(`{MODULES}/{schema}_Server.luau`, rewritten(server))
		fs.writeFile(`{MODULES}/{schema}_Types.luau`, types)
	end
end

-- Volt's own code is held to the default checker, the modules a game commits to both
local old: boolean = analyze({}, { "src", "tests", "tools", MODULES })
local new: boolean = analyze({ SOLVER, "--ignore=src/**", "--ignore=tests/**" }, { MODULES })

process.exit((old and new) and 0 or 1)
