--[[
    Proves watch mode: the signature moves when a schema file is rewritten
    or joins its folder and for no other file, a poll compiles at once and
    then only once a change has gone still, a second compile in one process
    gives the first one's text, the command rewrites its modules as the
    schema is edited until it is killed, and --watch with --check exits 2
--]]

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local scratch = require("./Scratch")
local TargetsTypes = require("@volt/Compiler/Config/Types/Targets")
local Watch = require("@volt/Compiler/Watch")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Extra = TargetsTypes.Extra

-- The command run in the background, with what it has written to stderr so far and whether it has ended
type Run = { child: process.ChildProcess, errors: string, ended: boolean }

local EXAMPLE: string = "tests/Schemas/Example.volt"
local EXPORTS: string = fs.readFile("tests/Schemas/Exports.volt") -- A test schema whose outputs sit beside it
local STEP: number = 0.05 -- Between two looks at a file, and longer than the millisecond its modification time counts in
local START: number = 10 -- The longest the command may take to start and write its modules
local SETTLE: number = 2 -- The longest it may take to write them again after an edit

-- Polls a condition for at most a number of seconds, so a test ends whatever the command does
local function within(seconds: number, condition: () -> boolean): boolean
	for _ = 1, math.ceil(seconds / STEP) do
		if condition() then
			return true
		end

		task.wait(STEP)
	end

	return condition()
end

local function holds(path: string, text: string): boolean
	return fs.isFile(path) and fs.readFile(path):find(text, 1, true) ~= nil
end

-- Starts the command in the background, reading its stderr as it comes until it ends
local function start(...: string): Run
	local run: Run = { child = process.create("lune", { "run", "src/Compiler", ... }), errors = "", ended = false }

	task.spawn(function ()
		local chunk: string? = run.child.stderr:read()

		while chunk do
			run.errors ..= chunk
			chunk = run.child.stderr:read()
		end

		run.ended = true
	end)

	return run
end

-- Every file one compile gives, by its path, as one text
local function joined(client: string, server: string, types: string, extra: { Extra }): string
	local parts: { string } = { client, server, types }

	for _, piece: Extra in extra do
		table.insert(parts, `{piece.output}\n{piece.text}`)
	end

	return table.concat(parts, "\n")
end

describe("Watch", function ()
	test("reads a rewritten schema file and one joining the folder, and no other file", function ()
		local folder: string = scratch("Signature")
		local game: string = `{folder}/Game.volt`

		fs.writeFile(game, EXPORTS)

		local first: string = Watch.signature({ folder })

		-- An output, a file of another kind and a schema file in a subfolder are none of the command's
		task.wait(STEP)
		fs.writeFile(`{folder}/Client.luau`, "")
		fs.writeFile(`{folder}/Notes.txt`, "")
		fs.writeDir(`{folder}/Old`)
		fs.writeFile(`{folder}/Old/Game.volt`, EXPORTS)

		expect(Watch.signature({ folder })).is(first)

		fs.writeFile(game, EXPORTS)

		local rewritten: string = Watch.signature({ folder })

		expect(rewritten).never_is(first)

		fs.writeFile(`{folder}/Types.volt`, "")
		expect(Watch.signature({ folder })).never_is(rewritten)

		-- A file named on its own reads as missing once it is gone
		local named: string = Watch.signature({ game })

		fs.removeFile(game)
		expect(Watch.signature({ game })).never_is(named)
		expect(Watch.signature({ game })).is(`{game} missing`)

		fs.removeDir(folder)
	end)

	test("compiles on the first poll, never on an unchanged signature, and on a change once it reads twice", function ()
		local state: Watch.State = {}

		expect(Watch.due(state, "a")).is(true)
		expect(Watch.due(state, "a")).is(false)

		-- A save that writes in bursts compiles once, when it has gone still
		expect(Watch.due(state, "b")).is(false)
		expect(Watch.due(state, "c")).is(false)
		expect(Watch.due(state, "c")).is(true)
		expect(Watch.due(state, "c")).is(false)

		-- A change undone before it went still leaves what was compiled
		expect(Watch.due(state, "d")).is(false)
		expect(Watch.due(state, "c")).is(false)
		expect(Watch.due(state, "c")).is(false)
	end)

	test("compiles a schema a second time in one process to the text of the first", function ()
		for _, name: string in { "Example", "Sharded" } do
			local text: string = fs.readFile(`tests/Schemas/{name}.volt`)

			expect(joined(Generated.modules(name, text))).is(joined(Generated.modules(name, text)))
		end
	end)

	test("rewrites the modules after an edit, goes on past an error or a missing schema, and is killed", function ()
		local folder: string = scratch("Command")
		local schema: string = `{folder}/Watched.volt`
		local client: string = `{folder}/Client.luau`

		fs.writeFile(schema, EXPORTS)

		local run: Run = start(schema, "--watch", "--quiet")
		local ok: boolean, problem: any = pcall(function ()
			expect(within(START, function ()
				return holds(client, "Ping")
			end)).is(true)

			fs.writeFile(schema, (EXPORTS:gsub("Ping", "Pong")))
			expect(within(SETTLE, function ()
				return holds(client, "Pong")
			end)).is(true)

			-- A broken edit's diagnostic is printed, so is a schema gone missing, and the edit after them is written
			fs.writeFile(schema, (EXPORTS:gsub("from: Client", "from Client")))
			expect(within(SETTLE, function ()
				return run.errors:find(`{schema}:`, 1, true) ~= nil
			end)).is(true)

			fs.removeFile(schema)
			expect(within(SETTLE, function ()
				return run.errors:find(`volt: {schema} is missing`, 1, true) ~= nil
			end)).is(true)

			fs.writeFile(schema, (EXPORTS:gsub("Ping", "Knock")))
			expect(within(SETTLE, function ()
				return holds(client, "Knock")
			end)).is(true)
		end)

		-- Killed whatever the steps raised, so the command never outlives its test
		run.child:kill()
		run.child:status()

		if not ok then
			error(problem, 0)
		end

		expect(run.errors:find("error V2001", 1, true) ~= nil).is(true)
		expect(run.errors:find("internal error", 1, true) == nil).is(true)

		fs.removeDir(folder)
	end)

	test("exits 2 on --watch with --check before it compiles", function ()
		local run: Run = start(EXAMPLE, "--check", "--watch")
		local ended: boolean = within(START, function ()
			return run.ended
		end)

		-- Its stderr can close a moment before it exits, and a kill in that moment would take the place of its code
		if not ended then
			run.child:kill()
		end

		expect(ended).is(true)
		expect(run.child:status().code).is(2)
		expect(run.errors:sub(1, 6)).is("usage:")
	end)
end)
