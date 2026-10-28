--[[
    The parser's instance type, written out so the files merged onto the
    class can type self without requiring it: its fields, then the methods
    each of its files defines, one part per file, joined into the one Parser
--]]

--!strict
local Diagnostics = require("../../Diagnostics")
local Lexer = require("../../Lexer")
local Options = require("../Options")
local Schema = require("./Schema")

type Declaration = Schema.Declaration
type Diagnostics = Diagnostics.Diagnostics
type Field = Schema.Field
type Kind = Lexer.Kind
type Options = Schema.Options
type Pack = Schema.Pack
type Range = Schema.Range
type Span = Diagnostics.Span
type Spec = Options.Spec
type Token = Lexer.Token
type Type = Schema.Type

export type Fields = {
	_tokens: { Token },
	_diagnostics: Diagnostics,
	_index: number, -- The lookahead token
	_depth: number, -- Brackets opened and not yet closed
	_options: Options,
	_declared: boolean, -- Set by the first declaration, after which an option is out of place
}

export type Own = {
	declarations: (self: Parser, close: string?) -> { Declaration },
	synchronise: (self: Parser, depth: number, close: string?) -> (),
	declaration: (self: Parser) -> Declaration?,
	option: (self: Parser) -> (),
	typeDeclaration: (self: Parser) -> Declaration,
	message: (self: Parser, shape: { Spec }) -> Declaration,
	namespace: (self: Parser) -> Declaration,
	fail: (self: Parser, code: string, message: string, span: Span) -> never,
}

export type Tokens = {
	describe: (self: Parser, token: Token) -> string,
	peek: (self: Parser, ahead: number?) -> Token,
	at: (self: Parser, value: string) -> boolean,
	consume: (self: Parser) -> Token,
	previous: (self: Parser) -> Token,
	expect: (self: Parser, kind: Kind, value: string?) -> Token,
	key: (self: Parser) -> Token,
	name: (self: Parser) -> Token,
	skip: (self: Parser, close: string?) -> (),
	list: (self: Parser, close: string, item: () -> ()) -> (),
}

export type Records = {
	record: (self: Parser, target: { [string]: any }, shape: { Spec }, label: string) -> (),
	entry: (self: Parser, target: { [string]: any }, shape: { Spec }, key: Token, label: string, close: string?) -> (),
	value: (self: Parser, spec: Spec, key: string) -> any,
}

export type TypeForms = {
	type: (self: Parser) -> Type,
	postfix: (self: Parser) -> Type,
	atom: (self: Parser) -> Type,
	roblox: (self: Parser, token: Token) -> Type,
	struct: (self: Parser, start: number) -> Type,
	enum: (self: Parser, start: number) -> Type,
	fields: (self: Parser, open: string, close: string) -> { Field },
	pack: (self: Parser) -> Pack,
	bounds: (self: Parser) -> Range?,
	range: (self: Parser) -> Range,
}

export type Parser = Fields & Own & Tokens & Records & TypeForms

return {}
