--[[
    The problems found while compiling one schema. Every stage reports into
    it with a code, a message and a span, and it renders each entry as a
    location line in the file the span falls in and a two-line excerpt of
    it with the span underlined, so one run shows every problem in a schema
--]]

--!strict
local Diagnostics = {}
Diagnostics.__index = Diagnostics

local Source = require("./Source")

type File = Source.File
type Source = Source.Source

export type Span = { start: number, finish: number }
export type Diagnostic = { severity: string, code: string, message: string, span: Span }

type Fields = {
	source: Source,
	list: { Diagnostic },
	errors: number,
}

function Diagnostics.new(source: Source): Self
	return setmetatable({
		source = source,
		list = {} :: { Diagnostic },
		errors = 0,
	}, Diagnostics)
end

--[[
    Records an error. The span is any table carrying start and finish byte
    offsets, which every token and every parsed node does
--]]

function Diagnostics.error(self: Self, code: string, message: string, span: Span)
	self.errors += 1
	table.insert(self.list, { severity = "error", code = code, message = message, span = span })
end

--[[
    Records a warning, which never fails a build
--]]

function Diagnostics.warn(self: Self, code: string, message: string, span: Span)
	table.insert(self.list, { severity = "warning", code = code, message = message, span = span })
end

--[[
    Renders every diagnostic in the order it was reported. Each is a
    location line, the source line it points at, and an underline of the
    span clipped to that line, with a blank line between entries
--]]

function Diagnostics.render(self: Self): string
	local source: Source = self.source
	local rendered: { string } = {}

	for _, diagnostic: Diagnostic in self.list do
		local span: Span = diagnostic.span
		local file: File = source:file(span.start)
		local line: number, column: number = source:position(span.start)
		local text: string = source:lineText(line)
		local lineEnd: number = span.start - column + #text
		local length: number = math.max(1, math.min(span.finish, lineEnd) - span.start + 1)
		local shown: number = line - file.line + 1 -- Counted from the top of the span's own file

		-- Tabs are kept in the underline's lead so the carets line up with the excerpt
		local lead: string = text:sub(1, column - 1):gsub("[^\t]", " ")
		local location: string =
			`{file.path}:{shown}:{column}: {diagnostic.severity} {diagnostic.code}: {diagnostic.message}`
		local excerpt: string = string.format("%5d | %s", shown, text)
		local underline: string = `      | {lead}{string.rep("^", length)}`

		table.insert(rendered, `{location}\n{excerpt}\n{underline}`)
	end

	return table.concat(rendered, "\n\n")
end

export type Diagnostics = Self
type Self = typeof(setmetatable({} :: Fields, Diagnostics))

return Diagnostics
