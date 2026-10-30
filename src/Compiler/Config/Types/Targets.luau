--[[
    The assembler's instance type: its fields, the methods each of its
    files defines, one part per file, what an event's or a function's API
    entry is built from once the walk of its messages is done, and what
    each entry's walk recorded for a side that shards
--]]

--!strict
local Blocks = require("../../Blocks")
local Diagnostics = require("../../Diagnostics")
local Emit = require("./Emit")
local Pieces = require("../../Targets/Pieces")
local Schema = require("./Schema")

type Block = Blocks.Block
type Declaration = Schema.Declaration
type Diagnostics = Diagnostics.Diagnostics
export type Emit = Emit.Emit
type Event = Schema.Event
type Field = Schema.Field
type File = Schema.File
type Function = Schema.Function
type Pack = Schema.Pack
type Send = Pieces.Send
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration

-- What an event's API entry is built from once it is walked: its ids on this side, its writer's signature and its listener's
export type Walked = {
	id: number?, -- Heard as
	out: number?, -- Sent as
	stream: number?, -- The channel it rides, by number, when it rides one
	delta: boolean, -- Whether it is @delta, so every fire goes through the runtime's delta
	label: string,
	typed: string,
	arguments: string,
	listener: string,
	iterator: string,
	pack: string, -- The types it carries, as a handle type takes them
}

-- What a function's API entry is built from once it is walked: this side's id, the call's signature, what it returns and the handler's
export type Exchanged = {
	id: number,
	label: string,
	typed: string,
	arguments: string,
	result: string, -- What invoke is annotated as returning: the error tuple, or nothing said for a promise
	handler: string,
	pack: string, -- The types the call carries, as a handle type takes them
	returns: string, -- And the types it returns, likewise
}

-- An event's, a function's or an exported type's API entry as its walk left it, which a shard takes whole
export type Entry = {
	path: string,
	declaration: Declaration, -- Where a diagnostic about the entry points
	value: string, -- Its handle, as the API table holds it under its name
	first: number, -- The functions its walk added to _functions, first past last when it added none
	last: number,
}

-- A file the compiler writes beside a side's module, its output relative to the options file's folder
export type Extra = { output: string, text: string }

export type Fields = {
	_file: File,
	_side: string,
	_server: boolean,
	_casing: string,
	_emitter: Emit,
	_label: string?,
	_toServer: number,
	_toClient: number,
	_promise: boolean,
	_reversed: boolean,
	_ordered: boolean,
	_dictionary: boolean,
	_streams: { string },
	_sends: { Send },
	_reserve: { string },
	_functions: { string },
	_messages: { [number]: string },
	_outgoing: { [number]: string },
	_registry: { [string]: { string } },
	_entries: { Entry },
}

export type Own = {
	render: (self: Targets, hash: number, name: string, diagnostics: Diagnostics) -> (string, { Extra }),
	header: (self: Targets, about: string, promised: boolean) -> string,
	aliases: (self: Targets, shard: boolean) -> { string },
	start: (self: Targets, hash: number) -> string,
	method: (self: Targets, name: string) -> string,
	count: (self: Targets, declarations: { Declaration }) -> (),
	mark: (self: Targets, declarations: { Declaration }) -> (),
}

export type Api = {
	api: (self: Targets, values: { [string]: string }?) -> string,
	declarations: (self: Targets, declarations: { Declaration }, values: { [string]: string }?) -> { string },
	event: (self: Targets, event: Event) -> string,
	call: (self: Targets, declaration: Function) -> string,
	export: (self: Targets, declaration: TypeDeclaration) -> string,
	registry: (self: Targets) -> string,
}

export type Messages = {
	sends: (
		write: Block,
		reliable: boolean,
		fixed: number,
		data: (Type | Pack)?,
		stream: string?,
		delta: boolean?
	) -> string?,
	parameters: (data: (Type | Pack)?) -> { Field },
	walk: (self: Targets, event: Event, fires: boolean, hears: boolean) -> Walked,
	exchange: (self: Targets, declaration: Function) -> Exchanged,
}

export type Shards = {
	pack: (self: Targets, pieces: { string }, fixed: number, diagnostics: Diagnostics) -> { { Entry } },
	shard: (self: Targets, entries: { Entry }, pieces: { string }, head: string, schema: string) -> string,
	sharded: (
		self: Targets,
		hash: number,
		name: string,
		pieces: { string },
		diagnostics: Diagnostics
	) -> (string, { Extra }),
}

export type Targets = Fields & Own & Api & Messages & Shards

return {}
