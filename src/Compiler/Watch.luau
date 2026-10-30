--[[
    The schema files the command reads, and watch mode over them: a
    signature of their modification times, the decision to compile that
    it drives, and the poll that compiles again whenever the files change
    and then go still, until the process is stopped
--]]

--!strict
local Watch = {}

local fs = require("@lune/fs")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

local Output = require("./Config/Output")

-- The signature compiled last, nil until the first compile, and the one read at the poll before
export type State = { compiled: string?, last: string? }

local WATCH_SECONDS: number = Output.watchSeconds
local EXTENSION: string = "%.volt$" -- What makes a file a schema file
local MISSING: string = "missing" -- What a path that does not exist reads as in a signature

function Watch.isSchema(path: string): boolean
	return path:match(EXTENSION) ~= nil and fs.isFile(path)
end

--[[
    The schema files a command's paths name, in the order they compile:
    every schema file directly inside a folder, by name and none from its
    subfolders, or the one file, then each further file as given
--]]

function Watch.files(paths: { string }): { string }
	local files: { string } = {}

	if fs.isDir(paths[1]) then
		local folder: string = (paths[1]:gsub("[/\\]+$", ""))

		for _, name: string in fs.readDir(folder) do
			if Watch.isSchema(`{folder}/{name}`) then
				table.insert(files, `{folder}/{name}`)
			end
		end

		table.sort(files)
	else
		table.insert(files, paths[1])
	end

	table.move(paths, 2, #paths, #files + 1, files)
	return files
end

-- Every file the paths name with its modification time, or missing, one to a line, listed again at every call
function Watch.signature(paths: { string }): string
	local lines: { string } = {}

	for _, path: string in Watch.files(paths) do
		local metadata: fs.Metadata = fs.metadata(path)
		local stamp: string = MISSING

		if metadata.exists then
			stamp = `{metadata.modifiedAt.unixTimestampMillis}`
		end

		table.insert(lines, `{path} {stamp}`)
	end

	return table.concat(lines, "\n")
end

--[[
    Whether this poll compiles: the first does at once, and after it one
    whose signature differs from the one compiled last and matches the one
    read at the poll before, so a save that writes in bursts compiles once,
    when the files have gone still
--]]

function Watch.due(state: State, signature: string): boolean
	local due: boolean = state.compiled == nil or signature ~= state.compiled and signature == state.last

	state.last = signature

	if due then
		state.compiled = signature
	end

	return due
end

-- Compiles on every poll that is due, printing an error the compiler raises and going on, until the process is stopped
function Watch.run(paths: { string }, compile: () -> number)
	local state: State = {}

	repeat
		if Watch.due(state, Watch.signature(paths)) then
			local ok: boolean, problem: any = pcall(compile)

			if not ok then
				stdio.ewrite(`volt: internal error: {problem}\n`)
			end
		end
	until not task.wait(WATCH_SECONDS) -- It returns the time it waited, so only stopping the process ends the loop
end

return Watch
