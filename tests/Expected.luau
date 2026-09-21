--[[
    The golden file a generator test compares its text against: written
    from the text when the runner was given --update, after a reviewed
    generator change, and read back either way, or empty when there is
    none yet
--]]

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")

local UPDATE: boolean = table.find(process.args, "--update") ~= nil

return function (directory: string, name: string, text: string): string
	local golden: string = `{directory}/{name}.luau`

	if UPDATE then
		if not fs.isDir(directory) then
			fs.writeDir(directory)
		end

		fs.writeFile(golden, text)
	end

	return fs.isFile(golden) and fs.readFile(golden) or ""
end
