--[[
    Formats every first-party .luau file with StyLua and then restores the
    space after the function keyword of anonymous functions, which StyLua
    removes and the house style requires. Vendored code is left alone
--]]

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")

local ROOTS: { string } = { "src", "tests", "tools" }
local VENDORED: string = "tests/tiniest"

local files: { string } = {}

--[[
    Collects every .luau file under a directory, skipping the vendored tree
--]]

local function collect(directory: string)
	for _, name: string in fs.readDir(directory) do
		local path: string = `{directory}/{name}`

		if path == VENDORED then
			continue
		end

		if fs.isDir(path) then
			collect(path)
		elseif name:match("%.luau$") then
			table.insert(files, path)
		end
	end
end

for _, root: string in ROOTS do
	collect(root)
end

-- Whiteoak TODO: one command line carries every path and caps out near a thousand files on Windows; batch it then
local result = process.exec("stylua", files, { stdio = "forward" })

if not result.ok then
	process.exit(result.code)
end

-- Only an anonymous function puts a parenthesis straight after the keyword, so the restore is safe
for _, path: string in files do
	local source: string = fs.readFile(path)
	local restored: string = source:gsub("%f[%w_]function%(", "function (")

	if restored ~= source then
		fs.writeFile(path, restored)
	end
end
