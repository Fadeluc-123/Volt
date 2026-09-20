--[[
    A schema file as the compiler sees it: its path, its text and the byte
    offset where every line starts, so a span renders as a line and column
    and the line it sits on can be excerpted in a diagnostic
--]]

--!strict
local Source = {}
Source.__index = Source

export type Source = typeof(setmetatable({} :: {
	path: string,
	text: string,
	_lineStarts: { number }
}, Source))

function Source.new(path: string, text: string): Source
	local lineStarts: { number } = { 1 }
	local newline: number? = text:find("\n", 1, true)

	while newline do
		table.insert(lineStarts, newline + 1)
		newline = text:find("\n", newline + 1, true)
	end

	return setmetatable({
		path = path,
		text = text,
		_lineStarts = lineStarts,
	}, Source)
end

--[[
    Renders a byte offset as its line and column, both counted from one.
    An offset one past the end of the text lands after the last character,
    which is where an end-of-file diagnostic points
--]]

function Source:position(offset: number): (number, number)
	local line: number = #self._lineStarts
	while self._lineStarts[line] > offset do
		line -= 1
	end
	return line, offset - self._lineStarts[line] + 1
end

--[[
    The text of one line without its line ending, for excerpts
--]]

function Source:lineText(line: number): string
	return self.text:match("[^\r\n]*", self._lineStarts[line]) :: string
end

return Source
