--[[
    Proves the volt command compiles one file, or a folder and the further
    files it reuses, to the modules the options file asks for, names each
    module that is missing or out of date on --check, prints the canonical
    form on --ast, drops the summary on --quiet and exits 2 on bad arguments
--]]

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")

local Suite = require("./Suite")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

local EXAMPLE: string = "tests/Schemas/Example.volt"
local EXPORTS: string = "tests/Schemas/Exports.volt" -- The one test schema whose outputs sit beside it
local SPLIT: string = "tests/Schemas/Split" -- An arena's schema folder and the game's files it reuses
local SCRATCH: string = `{process.env.TEMP or process.env.TMPDIR or "/tmp"}/VoltCompilerTest`

local function volt(...: string): process.ExecResult
	return process.exec("lune", { "run", "src/Compiler", ... })
end

-- A fresh folder for one test, emptied of whatever an earlier run left behind
local function scratch(name: string): string
	local directory: string = `{SCRATCH}/{name}`

	if fs.isDir(directory) then
		fs.removeDir(directory)
	end

	fs.writeDir(directory)
	return directory
end

local function crlf(path: string)
	fs.writeFile(path, (fs.readFile(path):gsub("\n", "\r\n")))
end

describe("Compiler", function ()
	test("checks what it wrote, line endings aside, and names each module missing or out of date", function ()
		local directory: string = scratch("Check")
		local schema: string = `{directory}/Schemas/Example.volt`
		local network: string = `{directory}/Shared/Network`

		fs.writeDir(`{directory}/Schemas`)
		fs.writeDir(network)
		fs.writeFile(schema, fs.readFile(EXAMPLE))

		local written: process.ExecResult = volt(schema, "--quiet")

		expect(written.code).is(0)
		expect(written.stdout).is("")

		local checked: process.ExecResult = volt(schema, "--check", "--ast")
		local line: string = "type Reference = string(1..64) -- 2..65 bytes, 2 references"
		local summary: string = `{schema}: ok, schema hash 0x`

		expect(checked.code).is(0)
		expect(checked.stderr).is("")
		expect(checked.stdout:find(line, 1, true) ~= nil).is(true)
		expect(checked.stdout:find(summary, 1, true) ~= nil).is(true)

		crlf(`{network}/Server.luau`)

		local quiet: process.ExecResult = volt(schema, "--check", "--quiet")

		expect(quiet.code).is(0)
		expect(quiet.stdout).is("")
		expect(quiet.stderr).is("")

		-- An edited module and two removed ones, each named once and nothing written back
		local client: string = `{network}/Client.luau`
		fs.writeFile(client, `{fs.readFile(client)}-- edited\n`)
		fs.removeFile(`{network}/Server.luau`)
		fs.removeFile(`{network}/Types.luau`)

		local stale: process.ExecResult = volt(schema, "--check")
		local named: string = table.concat({
			`{schema}: ../Shared/Network/Client.luau is out of date`,
			`{schema}: ../Shared/Network/Server.luau is missing`,
			`{schema}: ../Shared/Network/Types.luau is missing`,
			"",
		}, "\n")

		expect(stale.code).is(1)
		expect(stale.stdout).is("")
		expect(stale.stderr).is(named)
		expect(fs.isFile(`{network}/Server.luau`)).is(false)

		fs.removeDir(directory)
	end)

	test("writes both modules and the types beside a schema whose options put them there", function ()
		local directory: string = scratch("Write")
		local schema: string = `{directory}/Cli.volt`

		fs.writeFile(schema, fs.readFile(EXPORTS))

		local result: process.ExecResult = volt(schema, "--quiet")

		expect(result.code).is(0)
		expect(fs.readFile(`{directory}/Client.luau`):find("The client module Volt", 1, true) ~= nil).is(true)
		expect(fs.readFile(`{directory}/Server.luau`):find("The server module Volt", 1, true) ~= nil).is(true)
		expect(fs.readFile(`{directory}/Types.luau`):find("The types module Volt", 1, true) ~= nil).is(true)

		fs.removeDir(directory)
	end)

	test("compiles a folder and further files to what one file of them in the fixed order compiles to", function ()
		local root: string = scratch("Split")
		local arena: string = `{root}/arena/Schemas`
		local types: string = `{root}/game/Schemas/Types.volt`
		local combat: string = `{root}/game/Schemas/Combat.volt`
		local joined: string = `{root}/joined/Schemas/Arena.volt` -- Named like the options file, which names the schema

		fs.copy(SPLIT, root, true)
		fs.writeDir(`{root}/arena/Network`)
		fs.writeDir(`{root}/joined/Schemas`)
		fs.writeDir(`{root}/joined/Network`)

		-- The options file, then the folder's other files by name, then the further files as given
		local texts: { string } = {}
		for _, path: string in { `{arena}/Arena.volt`, `{arena}/Round.volt`, `{arena}/Types.volt`, types, combat } do
			table.insert(texts, fs.readFile(path))
		end

		fs.writeFile(joined, table.concat(texts, "\n"))

		-- A schema file in a subfolder is not the folder's, or it would set the options a second time
		fs.writeDir(`{arena}/Old`)
		fs.writeFile(`{arena}/Old/Arena.volt`, fs.readFile(`{arena}/Arena.volt`))

		local single: process.ExecResult = volt(joined)
		local split: process.ExecResult = volt(arena, types, combat)
		local summary: string = `{arena}/Arena.volt: ok, schema hash 0x`

		expect(single.code).is(0)
		expect(split.code).is(0)
		expect((split.stdout:find(summary, 1, true))).is(1)
		expect(split.stdout:match("0x%x+")).is(single.stdout:match("0x%x+"))

		for _, name: string in { "Client", "Server", "Types" } do
			expect(fs.readFile(`{root}/arena/Network/{name}.luau`)).is(fs.readFile(`{root}/joined/Network/{name}.luau`))
		end

		-- A module turned to CRLF still matches, an emptied one and a removed one do not
		crlf(`{root}/arena/Network/Client.luau`)
		expect(volt(arena, types, combat, "--check", "--quiet").code).is(0)

		fs.writeFile(`{root}/arena/Network/Server.luau`, "")
		fs.removeFile(`{root}/arena/Network/Types.luau`)

		local stale: process.ExecResult = volt(arena, types, combat, "--check")
		local named: string = table.concat({
			`{arena}/Arena.volt: ../Network/Server.luau is out of date`,
			`{arena}/Arena.volt: ../Network/Types.luau is missing`,
			"",
		}, "\n")

		expect(stale.code).is(1)
		expect(stale.stderr).is(named)

		fs.removeDir(root)
	end)

	test("reports an option outside the options file and a name declared in two files", function ()
		local root: string = scratch("Clash")
		local arena: string = `{root}/arena/Schemas`
		local types: string = `{root}/game/Schemas/Types.volt`
		local combat: string = `{root}/game/Schemas/Combat.volt`

		fs.copy(SPLIT, root, true)

		-- The arena's own types set an option and declare everything the game's types do
		local own: string = fs.readFile(`{arena}/Types.volt`)
		local reused: string = fs.readFile(types)
		fs.writeFile(`{arena}/Types.volt`, `option casing = snake\n{own}{reused}`)

		local result: process.ExecResult = volt(arena, types, combat)
		local options: string = `option "casing" is in a second file; options are set in {arena}/Arena.volt`
		local option: string = `{arena}/Types.volt:1:8: error V2010: {options}`
		local twice: string = `{types}:1:8: error V3002: "Hit" is declared twice`

		expect(result.code).is(1)
		expect(result.stderr:find(option, 1, true) ~= nil).is(true)
		expect(result.stderr:find(twice, 1, true) ~= nil).is(true)

		fs.removeDir(root)
	end)

	test("exits 2 on no schema, a folder with none directly inside and a further file that is not one", function ()
		local broken: process.ExecResult = volt("stylua.toml")

		for _, result: process.ExecResult in { volt(), volt(SPLIT), volt(`{SPLIT}/arena/Schemas`, "stylua.toml") } do
			expect(result.code).is(2)
			expect(result.stderr:sub(1, 6)).is("usage:")
		end

		-- A first argument that is a file is read whatever its name, so a file that is not a schema fails to parse
		expect(broken.code).is(1)
		expect(broken.stderr:find("error V", 1, true) ~= nil).is(true)
	end)
end)
