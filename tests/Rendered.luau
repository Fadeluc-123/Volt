--[[
    The three lines a diagnostic renders as when it points at the nth
    occurrence of a needle in a schema text, so a test states what it
    expects without counting lines and columns by hand
--]]

--!strict
local Source = require("@volt/Compiler/Source")

return function (text: string, needle: string, message: string, nth: number?): string
	local source: Source.Source = Source.new("Test.volt", text)
	local start: number = 0

	for _ = 1, nth or 1 do
		start = source.text:find(needle, start + 1, true) :: number
	end

	local line: number, column: number = source:position(start)
	local excerpt: string = source:lineText(line)
	local lead: string = excerpt:sub(1, column - 1):gsub("[^\t]", " ")
	local carets: string = string.rep("^", #needle)

	return `Test.volt:{line}:{column}: {message}\n{string.format("%5d | %s", line, excerpt)}\n      | {lead}{carets}`
end
