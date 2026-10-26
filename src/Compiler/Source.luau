--[[
    A schema as the compiler sees it: the text of every file it is read
    from, one after another, the byte offset where every line starts and
    where every file starts, so a span renders as its own file's path, line
    and column, and the line it sits on can be excerpted in a diagnostic
--]]

--!strict
local Source = {}
Source.__index = Source

-- One file of the source: where its text starts and ends, and the index of its first line
export type File = { path: string, start: number, finish: number, line: number }

export type Source = typeof(setmetatable(
	{} :: {
		path: string,
		start: number,
		text: string,
		files: { File },
		_lineStarts: { number },
	},
	Source
))

--[[
    Records where every line after a newline starts, from the given offset
    of the text on
--]]

local function lines(lineStarts: { number }, text: string, from: number)
	local newline: number? = text:find("\n", from, true)

	while newline do
		table.insert(lineStarts, newline + 1)
		newline = text:find("\n", newline + 1, true)
	end
end

function Source.new(path: string, text: string): Source
	local lineStarts: { number } = { 1 }
	lines(lineStarts, text, 1)

	return setmetatable({
		path = path, -- The file that sets the options, which names the schema
		start = 1, -- Where that file starts, which is where a problem with the whole schema points
		text = text,
		files = { { path = path, start = 1, finish = #text, line = 1 } },
		_lineStarts = lineStarts,
	}, Source)
end

--[[
    Reads one more file of the schema in after the last. A newline goes
    between the two, so the file before ends on it, which is where its end
    of file points, and no token can run from one file into the next
--]]

function Source:add(path: string, text: string): File
	local start: number = #self.text + 2
	local file: File = { path = path, start = start, finish = start + #text - 1, line = #self._lineStarts + 1 }

	self.text = `{self.text}\n{text}`
	lines(self._lineStarts, self.text, start - 1)
	table.insert(self.files, file)

	return file
end

--[[
    Renders a byte offset as its line and column, both counted from one.
    An offset one past the end of a file lands after its last character,
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
    The file a byte offset falls in, the end of file after its text included
--]]

function Source:file(offset: number): File
	local index: number = #self.files
	while self.files[index].start > offset do
		index -= 1
	end
	return self.files[index]
end

--[[
    The text of one line without its line ending, for excerpts
--]]

function Source:lineText(line: number): string
	return self.text:match("[^\r\n]*", self._lineStarts[line]) :: string
end

return Source
