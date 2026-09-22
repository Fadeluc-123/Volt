--[[
    Builds the volt binaries: darklua bundles the compiler into one file,
    lune build turns that file into an executable per target, and tar
    archives each one for the GitHub Release Rokit installs from. Every
    artefact lands under build/
--]]

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local ENTRY: string = "src/Compiler/init.luau"
local FOLDER: string = "build"
local BUNDLE: string = `{FOLDER}/volt.luau`
local CONFIG: string = `{FOLDER}/darklua.json`
local TARGETS: { string } = { "windows-x86_64", "linux-x86_64", "linux-aarch64", "macos-x86_64", "macos-aarch64" }

-- The bundle resolves requires as Luau does, leaves Lune's own libraries to the runtime and drops the types the analyzer has checked
local DARKLUA: { [string]: any } = {
	rules = { "remove_types" },
	bundle = { require_mode = { name = "luau" }, excludes = { "@lune/**" } },
}

-- Runs one tool with its output forwarded, and stops the build at the first that fails
local function run(program: string, arguments: { string })
	local result = process.exec(program, arguments, { stdio = "forward" })

	if not result.ok then
		process.exit(result.code)
	end
end

fs.writeDir(FOLDER)
fs.writeFile(CONFIG, serde.encode("json", DARKLUA, true))
run("darklua", { "process", "--config", CONFIG, ENTRY, BUNDLE })

for _, target: string in TARGETS do
	local binary: string = target:match("^windows") and "volt.exe" or "volt"

	run("lune", { "build", BUNDLE, "--output", `{FOLDER}/{binary}`, "--target", target })
	run("tar", { "-czf", `{FOLDER}/volt-{target}.tar.gz`, "-C", FOLDER, binary })
end
