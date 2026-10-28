--[[
    The assembler's instance type: its fields, the methods each of its
    files defines, one part per file, and what an event's or a function's
    API entry is built from once the walk of its messages is done
--]]

--!strict
local Blocks = require("../../Blocks")
local Emit = require("./Emit")
local Schema = require("./Schema")

type Block = Blocks.Block
type Declaration = Schema.Declaration
type Emit = Emit.Emit
type Event = Schema.Event
type Field = Schema.Field
type File = Schema.File
type Function = Schema.Function
type Pack = Schema.Pack
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration

-- What an event's API entry is built from once it is walked: its ids on this side, its writer's signature and its listener's
export type Walked = {
	id: number?, -- Heard as
	out: number?, -- Sent as
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

export type Fields = {
	_file: File,
	_side: string,
	_server: boolean,
	_casing: string,
	_emitter: Emit,
	_toServer: number,
	_toClient: number,
	_promise: boolean,
	_functions: { string },
	_messages: { [number]: string },
	_outgoing: { [number]: string },
	_registry: { [string]: { string } },
}

export type Own = {
	render: (self: Targets, hash: number, name: string) -> string,
	header: (self: Targets, name: string) -> string,
	start: (self: Targets, hash: number) -> string,
	method: (self: Targets, name: string) -> string,
	count: (self: Targets, declarations: { Declaration }) -> (),
}

export type Api = {
	api: (self: Targets) -> string,
	declarations: (self: Targets, declarations: { Declaration }) -> { string },
	event: (self: Targets, event: Event) -> string,
	call: (self: Targets, declaration: Function) -> string,
	export: (self: Targets, declaration: TypeDeclaration) -> string,
	registry: (self: Targets) -> string,
}

export type Messages = {
	sends: (write: Block, reliable: boolean, fixed: number, data: (Type | Pack)?) -> string?,
	parameters: (data: (Type | Pack)?) -> { Field },
	walk: (self: Targets, event: Event, fires: boolean, hears: boolean) -> Walked,
	exchange: (self: Targets, declaration: Function) -> Exchanged,
}

export type Targets = Fields & Own & Api & Messages

return {}
