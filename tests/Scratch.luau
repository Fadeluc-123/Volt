--[[
    A fresh folder for one test under the system's temporary folder,
    emptied of whatever an earlier run left behind, for a test that runs
    the command, since it writes its modules beside the schema
--]]

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")

local ROOT: string = `{process.env.TEMP or process.env.TMPDIR or "/tmp"}/VoltTests`

return function (name: string): string
	local directory: string = `{ROOT}/{name}`

	if fs.isDir(directory) then
		fs.removeDir(directory)
	end

	fs.writeDir(directory)
	return directory
end
