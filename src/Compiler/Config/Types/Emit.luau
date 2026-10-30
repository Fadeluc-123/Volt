--[[
    The emitter's instance type: its fields, and the methods each of its
    files defines, one part per file, the walks of each kind of type in
    the part named after the sibling that holds them
--]]

--!strict
local Blocks = require("../../Blocks")
local Schema = require("./Schema")

type Block = Blocks.Block
type Pack = Schema.Pack
type Range = Schema.Range
type Roblox = Schema.Roblox
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration

export type Fields = {
	_validate: boolean,
	_known: boolean,
	_constants: { [string]: string },
	_names: { [string]: boolean },
	_shared: { [TypeDeclaration]: boolean },
	_checked: { [TypeDeclaration]: boolean },
	helpers: { [string]: boolean },
	constants: { string },
	functions: { string },
}

export type Own = {
	block: (self: Emit, node: Type | Pack, write: Block, read: Block) -> ({ string }, { string }),
	mark: (self: Emit, node: Type | Pack) -> (),
	shared: (self: Emit, target: TypeDeclaration) -> string,
	call: (self: Emit, target: TypeDeclaration, write: Block, read: Block, value: string, hint: string) -> string,
	type: (self: Emit, node: Type, write: Block, read: Block, value: string, hint: string, path: string) -> string,
	shape: (self: Emit, write: Block, value: string, luauType: string, path: string) -> (),
	validating: (self: Emit, on: boolean) -> boolean,
	constant: (self: Emit, key: string, hint: string, render: (string) -> string) -> string,
}

export type Scalars = {
	number: (self: Emit, node: Type, write: Block, read: Block, value: string, hint: string, path: string) -> string,
	checked: (self: Emit, node: Type, write: Block, value: string, path: string) -> (),
	exact: (self: Emit, read: Block, name: string, at: number, result: string, path: string) -> (),
	quantised: (self: Emit, node: Type, write: Block, read: Block, value: string, hint: string, path: string) -> string,
	boolean: (self: Emit, write: Block, read: Block, value: string, path: string) -> string,
	bytes: (self: Emit, node: Type, write: Block, read: Block, value: string, hint: string, path: string) -> string,
	length: (
		self: Emit,
		range: Range?,
		write: Block,
		read: Block,
		measured: string,
		hint: string,
		path: string,
		unit: string
	) -> (string, number, number),
	unknown: (self: Emit, write: Block, read: Block, value: string, hint: string, path: string) -> string,
	literal: (self: Emit, node: Type, write: Block, value: string, path: string) -> string,
}

export type RobloxTypes = {
	roblox: (self: Emit, node: Roblox, write: Block, read: Block, value: string, hint: string, path: string) -> string,
	components: (
		self: Emit,
		node: Roblox,
		write: Block,
		read: Block,
		value: string,
		hint: string,
		path: string,
		result: string
	) -> (),
	corners: (
		self: Emit,
		node: Roblox,
		write: Block,
		read: Block,
		value: string,
		hint: string,
		path: string,
		result: string
	) -> (),
}

export type Frames = {
	cframe: (
		self: Emit,
		node: Roblox,
		write: Block,
		read: Block,
		value: string,
		hint: string,
		path: string,
		result: string
	) -> (),
	turn: (self: Emit, node: Type, write: Block, read: Block, value: string, hint: string, path: string) -> string,
	rotated: (
		self: Emit,
		node: Roblox,
		write: Block,
		read: Block,
		value: string,
		hint: string,
		path: string,
		result: string
	) -> (),
}

export type Instances = {
	instance: (
		self: Emit,
		node: Roblox,
		write: Block,
		read: Block,
		value: string,
		hint: string,
		path: string
	) -> string,
	awaited: (self: Emit, node: Roblox, write: Block, read: Block, value: string, hint: string, path: string) -> string,
}

export type Composites = {
	struct: (self: Emit, node: Type, write: Block, read: Block, value: string, hint: string, path: string) -> string,
	optional: (self: Emit, node: Type, write: Block, read: Block, value: string, hint: string, path: string) -> string,
	nested: (
		self: Emit,
		node: Type,
		write: Block,
		read: Block,
		value: string,
		hint: string,
		path: string,
		target: string,
		cast: string?
	) -> (),
	tag: (self: Emit, count: number, write: Block, read: Block) -> ((string) -> (), string),
	enum: (self: Emit, node: Type, write: Block, read: Block, value: string, hint: string, path: string) -> string,
	union: (self: Emit, node: Type, write: Block, read: Block, value: string, hint: string, path: string) -> string,
}

export type Collections = {
	array: (self: Emit, node: Type, write: Block, read: Block, value: string, hint: string, path: string) -> string,
	run: (
		self: Emit,
		write: Block,
		read: Block,
		hint: string,
		path: string,
		nodes: { Type },
		measured: string,
		count: string
	) -> (Block, Block),
	bitset: (self: Emit, range: Range?, write: Block, read: Block, value: string, hint: string, path: string) -> string,
	map: (self: Emit, node: Type, write: Block, read: Block, value: string, hint: string, path: string) -> string,
}

export type Replication = {
	delta: (self: Emit, node: Type, write: Block, read: Block) -> (string, string, string, string),
	dictionary: (
		self: Emit,
		target: TypeDeclaration,
		write: Block,
		read: Block,
		value: string,
		hint: string,
		path: string
	) -> string,
}

export type Emit = Fields & Own & Scalars & RobloxTypes & Frames & Instances & Composites & Collections & Replication

return {}
