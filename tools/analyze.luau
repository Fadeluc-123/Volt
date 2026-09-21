--[[
    Runs luau-lsp analyze over the source, tests and tools with the
    Roblox definitions the runtime's transport needs, fetched once from
    luau-lsp's repository at the pinned version into Definitions/
--]]

--!strict
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

local VERSION: string = "1.70.0" -- The luau-lsp pinned in rokit.toml, whose definitions match its analyzer
local URL: string = `https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/{VERSION}/scripts/globalTypes.d.luau`
local FOLDER: string = "Definitions"
local PATH: string = `{FOLDER}/globalTypes.d.luau`
local IGNORED: string = "tests/Golden/**" -- Generated modules are Roblox code, linted in consumers' games

if not fs.isFile(PATH) then
	local response = net.request(URL)

	assert(response.ok, `Could not fetch {URL}: {response.statusCode} {response.statusMessage}`)
	fs.writeDir(FOLDER)
	fs.writeFile(PATH, response.body)
end

local result = process.exec(
	"luau-lsp",
	{ "analyze", `--definitions={PATH}`, `--ignore={IGNORED}`, "src", "tests", "tools" },
	{ stdio = "forward" }
)

process.exit(result.code)
