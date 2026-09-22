--[[
    Runs luau-lsp analyze over the source, tests and tools with the
    Roblox definitions the runtime's transport needs, fetched once from
    luau-lsp's repository at the pinned version into Definitions/, and
    over a copy of each generated module golden with its requires pointed
    at this repository, which is how a consumer's game would see it
--]]

--!strict
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

local VERSION: string = "1.70.0" -- The luau-lsp pinned in rokit.toml, whose definitions match its analyzer
local URL: string = `https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/{VERSION}/scripts/globalTypes.d.luau`
local FOLDER: string = "Definitions"
local PATH: string = `{FOLDER}/globalTypes.d.luau`
local GOLDENS: string = `{FOLDER}/Goldens` -- The module goldens as a game requires them, rewritten here
local IGNORED: string = "tests/Golden/**" -- The goldens themselves require a package no sourcemap resolves here
local CHUNK: string = "Emit.luau" -- The emitter's chunk, which is a test's and not a module

-- A golden's requires as this repository resolves them: the runtime through the tests' alias, the promise as its stand-in
local function rewritten(text: string): string
	return (
		text:gsub('local ReplicatedStorage = game:GetService%("ReplicatedStorage"%)\n', "")
			:gsub("require%(ReplicatedStorage%.Packages%.Volt%)", 'require("@volt")')
			:gsub("require%(ReplicatedStorage%.Packages%.Promise%)", 'require("../../tests/Promise")')
	)
end

if not fs.isFile(PATH) then
	local response = net.request(URL)

	assert(response.ok, `Could not fetch {URL}: {response.statusCode} {response.statusMessage}`)
	fs.writeDir(FOLDER)
	fs.writeFile(PATH, response.body)
end

if fs.isDir(GOLDENS) then
	fs.removeDir(GOLDENS)
end

fs.writeDir(GOLDENS)

for _, schema: string in fs.readDir("tests/Golden") do
	for _, name: string in fs.readDir(`tests/Golden/{schema}`) do
		if name ~= CHUNK then
			fs.writeFile(`{GOLDENS}/{schema}_{name}`, rewritten(fs.readFile(`tests/Golden/{schema}/{name}`)))
		end
	end
end

local result = process.exec(
	"luau-lsp",
	{ "analyze", `--definitions={PATH}`, `--ignore={IGNORED}`, "src", "tests", "tools", GOLDENS },
	{ stdio = "forward" }
)

process.exit(result.code)
