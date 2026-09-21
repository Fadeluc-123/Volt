--[[
    Turns a schema's text into tokens. One string pattern per token kind is
    tried at the cursor in a fixed order; whitespace and comments produce
    nothing, an unterminated string or an unknown character is reported and
    the scan resumes on the next line, and the list always ends with eof
--]]

--!strict
local Diagnostics = require("./Diagnostics")
local Source = require("./Source")

type Diagnostics = Diagnostics.Diagnostics
type Source = Source.Source

export type Kind = "keyword" | "primitive" | "name" | "number" | "string" | "range" | "punctuation" | "eof"
export type Token = { kind: Kind, value: string, start: number, finish: number }

local KEYWORDS: { [string]: boolean } = {
	option = true,
	export = true,
	type = true,
	struct = true,
	enum = true,
	namespace = true,
	event = true,
	set = true,

	["function"] = true,
}

local PRIMITIVES: { [string]: boolean } = {
	u8 = true,
	u16 = true,
	u24 = true,
	u32 = true,
	u48 = true,
	u64 = true,

	i8 = true,
	i16 = true,
	i24 = true,
	i32 = true,
	i48 = true,
	i64 = true,
	f16 = true,
	f32 = true,
	f64 = true,

	q8 = true,
	q16 = true,

	boolean = true,
	string = true,
	buffer = true,
	unknown = true,
}

--[[
	Tried at the cursor in this order and the first match wins, so a comment
	is never a negative number, a float never stops at the dot of a range,
	and the range operator is seen before the dot of a namespaced name
--]]

local PATTERNS: { { pattern: string, kind: string } } = {
	{ pattern = "^%s+", kind = "skip" },
	{ pattern = "^%-%-[^\n]*", kind = "skip" },
	{ pattern = `^"[^"\n]*"`, kind = "string" },
	{ pattern = "^%-?%d+%.%d+", kind = "number" },
	{ pattern = "^%-?%d+", kind = "number" },
	{ pattern = "^[%a_][%w_]*", kind = "name" },
	{ pattern = "^%.%.", kind = "range" },
	{ pattern = "^[{}()%[%]<>:,=|?.]", kind = "punctuation" },
}

local Lexer = {}

--[[
    Finds the first pattern that matches at the cursor and returns its kind
    and the offset of its last byte, or nil when nothing matches there
--]]

local function matchAt(text: string, cursor: number): (string?, number)
	for _, entry: { pattern: string, kind: string } in PATTERNS do
		local finish: number? = select(2, text:find(entry.pattern, cursor))
		if finish then
			return entry.kind, finish
		end
	end

	return nil, cursor
end

--[[
    Scans the whole source into tokens, reporting into the diagnostics.
    Whitespace and comments produce no token, and the last token is eof
--]]

function Lexer.scan(source: Source, diagnostics: Diagnostics): { Token }
	local text: string = source.text
	local tokens: { Token } = {}
	local cursor: number = 1

	while cursor <= #text do
		local kind: string?, finish: number = matchAt(text, cursor)
		local value: string = text:sub(cursor, finish)

		-- Nothing matched, so report it and pick the scan up on the next line
		if kind == nil then
			local lineEnd: number = (text:find("\n", cursor, true) or #text + 1) - 1
			if value == `"` then
				diagnostics:error("V1001", `unterminated string`, { start = cursor, finish = lineEnd })
			else
				diagnostics:error("V1002", `unexpected character "{value}"`, { start = cursor, finish = cursor })
			end

			cursor = lineEnd + 2
			continue
		end

		if kind == "string" then
			value = value:sub(2, -2)
		elseif kind == "name" then
			kind = KEYWORDS[value] and "keyword" or PRIMITIVES[value] and "primitive" or "name"
		end

		if kind ~= "skip" then
			table.insert(tokens, { kind = kind :: Kind, value = value, start = cursor, finish = finish })
		end

		cursor = finish + 1
	end

	table.insert(tokens, { kind = "eof", value = "", start = #text + 1, finish = #text + 1 })
	return tokens
end

return Lexer
