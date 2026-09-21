--[[
    The primitives the parser reads its tokens through, merged onto the
    parser class: the lookahead, matching and consuming one token, the
    expectations that abandon a declaration when they fail, the names a
    record may use, and the skip past a value nobody wants
--]]

--!strict
local Tokens = {} :: any

local Lexer = require("../Lexer")
local Reserved = require("../Config/Reserved")

type Token = Lexer.Token

-- Consumed brackets move the depth, so a resync can tell which body it is in
local NESTING: { [string]: number } = {
	["{"] = 1,
	["("] = 1,
	["["] = 1,
	["<"] = 1,
	["}"] = -1,
	[")"] = -1,
	["]"] = -1,
	[">"] = -1,
}

--[[
    How a token reads in a message
--]]

function Tokens:describe(token: Token): string
	return token.kind == "eof" and "end of file"
		or token.kind == "string" and `string "{token.value}"`
		or `"{token.value}"`
end

--[[
    The token at the cursor, or the one a given distance ahead. Past the
    end it is always the eof token
--]]

function Tokens:peek(ahead: number?): Token
	return self._tokens[math.min(self._index + (ahead or 0), #self._tokens)]
end

--[[
    Whether the token at the cursor is the given keyword, name or
    punctuation. A string token never matches, whatever it holds
--]]

function Tokens:at(value: string): boolean
	local token: Token = self:peek()
	return token.kind ~= "string" and token.value == value
end

--[[
    Advances past the token at the cursor and returns it. The eof token is
    never passed, so every loop over the cursor ends
--]]

function Tokens:consume(): Token
	local token: Token = self:peek()
	if token.kind ~= "eof" then
		self._index += 1
	end
	if token.kind == "punctuation" then
		self._depth += NESTING[token.value] or 0
	end
	return token
end

function Tokens:previous(): Token
	return self._tokens[self._index - 1]
end

--[[
    Consumes the token at the cursor if it has the kind, and the value when
    one is given, or abandons the declaration
--]]

function Tokens:expect(kind: Lexer.Kind, value: string?): Token
	local token: Token = self:peek()
	if token.kind ~= kind or (value ~= nil and token.value ~= value) then
		local wanted: string = value and `"{value}"` or `a {kind}`
		self:fail("V2001", `expected {wanted}, got {self:describe(token)}`, token)
	end
	return self:consume()
end

--[[
    A record key: any name, including the keywords the schema also uses as
    keys, such as type
--]]

function Tokens:key(): Token
	local token: Token = self:peek()
	if token.kind ~= "name" and token.kind ~= "keyword" then
		self:fail("V2001", `expected a name, got {self:describe(token)}`, token)
	end
	return self:consume()
end

--[[
    A name that the generated code will spell out as a Luau identifier, so
    a reserved word is reported, though the parse carries on
--]]

function Tokens:name(): Token
	local token: Token = self:key()
	if Reserved.luau[token.value] then
		self._diagnostics:error("V2006", `"{token.value}" is a Luau reserved word and cannot be a name`, token)
	end
	return token
end

--[[
    Skips a value nobody wants: one token for an option, or everything up
    to the next comma or closing brace at this depth inside a record
--]]

function Tokens:skip(close: string?)
	local depth: number = self._depth
	repeat
		self:consume()
	until self:peek().kind == "eof" or close == nil or (self._depth == depth and (self:at(",") or self:at(close)))
end

--[[
    Parses comma-separated items up to the closing bracket, allowing a
    trailing comma, and consumes the bracket
--]]

function Tokens:list(close: string, item: () -> ())
	while not self:at(close) and self:peek().kind ~= "eof" do
		item()

		if not self:at(",") then
			break
		end

		self:consume()
	end

	self:expect("punctuation", close)
end

return Tokens
