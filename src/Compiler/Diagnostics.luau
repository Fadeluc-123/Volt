--[[
    The problems found while compiling one schema. Every stage reports into
    it with a code, a message and a span, and it renders each entry as a
    location line and a two-line excerpt of the source with the span
    underlined, so one run shows every problem in the file
--]]

--!strict
local Diagnostics = {} :: any
Diagnostics.__index = Diagnostics

local Source = require("./Source")

type Source = Source.Source

export type Span = { start: number, finish: number }
export type Diagnostic = { severity: string, code: string, message: string, span: Span }

export type Diagnostics = {
	source: Source,
	list: { Diagnostic },
	errors: number,
	error: (self: Diagnostics, code: string, message: string, span: Span) -> (),
	warn: (self: Diagnostics, code: string, message: string, span: Span) -> (),
	render: (self: Diagnostics) -> string,
}

function Diagnostics.new(source: Source)
	return setmetatable({
		source = source,
		list = {},
		errors = 0,
	}, Diagnostics)
end

--[[
    Records an error. The span is any table carrying start and finish byte
    offsets, which every token and every parsed node does
--]]

function Diagnostics:error(code: string, message: string, span: Span)
	self.errors += 1
	table.insert(self.list, { severity = "error", code = code, message = message, span = span })
end

--[[
    Records a warning, which never fails a build
--]]

function Diagnostics:warn(code: string, message: string, span: Span)
	table.insert(self.list, { severity = "warning", code = code, message = message, span = span })
end

--[[
    Renders every diagnostic in the order it was reported. Each is a
    location line, the source line it points at, and an underline of the
    span clipped to that line, with a blank line between entries
--]]

function Diagnostics:render(): string
	local source: Source = self.source
	local rendered: { string } = {}

	for _, diagnostic: Diagnostic in self.list do
		local span: Span = diagnostic.span
		local line: number, column: number = source:position(span.start)
		local text: string = source:lineText(line)
		local lineEnd: number = span.start - column + #text
		local length: number = math.max(1, math.min(span.finish, lineEnd) - span.start + 1)

		-- Tabs are kept in the underline's lead so the carets line up with the excerpt
		local lead: string = text:sub(1, column - 1):gsub("[^\t]", " ")
		local location: string =
			`{source.path}:{line}:{column}: {diagnostic.severity} {diagnostic.code}: {diagnostic.message}`
		local excerpt: string = string.format("%5d | %s", line, text)
		local underline: string = `      | {lead}{string.rep("^", length)}`

		table.insert(rendered, `{location}\n{excerpt}\n{underline}`)
	end

	return table.concat(rendered, "\n\n")
end

return Diagnostics
