--[[
    The nodes a parsed schema is made of, shared by every stage: the type
    forms, the declarations, the options and the file. Resolution fills
    path, target, references and the ids; the parser leaves them nil
--]]

--!strict
export type Span = { start: number, finish: number }

export type Range = { min: number?, max: number?, start: number, finish: number }
export type Parameter = { name: string, start: number, finish: number } -- A type parameter a generic declares

-- A spread entry has no name and a reference as its type, and Expand replaces it with the fields it names
export type Field = { name: string, type: Type, spread: boolean?, start: number, finish: number }
export type Variant = { name: string, fields: { Field }?, start: number, finish: number }
export type Pack = { kind: "pack", parameters: { Field }, start: number, finish: number }
export type Roblox = {
	kind: "roblox",
	name: string,
	generics: { Type }?,
	class: string?,
	item: string?,
	start: number,
	finish: number,
}

--[[
    A string primitive carries utf8 only when written string.utf8, a literal
    holds the one value it allows, and a reference to a type parameter holds
    the parameter's index in place of a target
--]]

export type Type =
	{ kind: "primitive", name: string, range: Range?, utf8: boolean?, start: number, finish: number }
	| Roblox
	| { kind: "struct", fields: { Field }, start: number, finish: number }
	| { kind: "enum", tag: string?, variants: { Variant }, start: number, finish: number }
	| { kind: "set", element: Type, range: Range?, start: number, finish: number }
	| { kind: "map", key: Type, value: Type, range: Range?, start: number, finish: number }
	| { kind: "array", element: Type, range: Range?, start: number, finish: number }
	| { kind: "optional", inner: Type, start: number, finish: number }
	| { kind: "union", members: { Type }, start: number, finish: number }
	| {
		kind: "reference",
		name: string,
		target: TypeDeclaration?,
		arguments: { Type }?,
		parameter: number?,
		start: number,
		finish: number,
	}
	| { kind: "literal", value: string | number | boolean, start: number, finish: number }

-- Keyed by the attribute's name without its @: an argument's number, or true for one that takes none
export type Attributes = { [string]: boolean | number }

export type TypeDeclaration = {
	kind: "type",
	name: string,
	export: boolean,
	type: Type,
	parameters: { Parameter }?, -- Absent when the declaration is no generic
	attributes: Attributes?, -- Absent when there are none
	spans: { [string]: Span }?, -- Where each attribute was written
	path: string?,
	references: number?,
	depth: number?, -- The deepest level a value may sit at, set only on a recursive type
	generic: TypeDeclaration?, -- The generic an instantiation is made from
	arguments: { Type }?, -- What an instantiation's parameters stand for
	label: string?, -- An instantiation's name as a Luau identifier
	start: number,
	finish: number,
}

export type Event = {
	kind: "event",
	name: string,
	from: string,
	type: string,
	call: string,
	data: (Type | Pack)?,
	queue: number?,
	rate: (number | string)?,
	timeout: number?, -- Seconds an AwaitedInstance waits on the client; unset, the file's
	channel: string?, -- The channel's name as written, then its full path once resolved
	attributes: Attributes?, -- As a type declaration's are
	spans: { [string]: Span },
	path: string?,
	toServer: number?,
	toClient: number?,
	start: number,
	finish: number,
}

-- An ordered reliable stream of its own, numbered from 1 by analysis in declaration order
export type Channel = { kind: "channel", name: string, path: string?, number: number?, start: number, finish: number }

export type Function = {
	kind: "function",
	name: string,
	from: string?, -- Server when the server calls one player's client; unset for a client's call
	data: (Type | Pack)?,
	yield: string?,
	timeout: number?,
	rate: (number | string)?,
	spans: { [string]: Span },
	path: string?,
	toServer: number?,
	toClient: number?,
	start: number,
	finish: number,

	["return"]: (Type | Pack)?,
}

export type Namespace = {
	kind: "namespace",
	name: string,
	declarations: { Declaration },
	path: string?,
	start: number,
	finish: number,
}

export type Declaration = TypeDeclaration | Event | Channel | Function | Namespace

export type Options = {
	clientOutput: string?,
	serverOutput: string?,
	typesOutput: string?,
	runtime: string?,
	scope: string?,
	casing: string?,
	writeValidation: boolean?,
	manualReplication: boolean?,
	flush: number?,
	flushBytes: number?,
	maxPacket: number?,
	maxPacketsPerSecond: number?,
	unreliableBudget: number?,
	stamp: boolean?,
	queue: number?,
	rate: (number | string)?,
	functionRate: (number | string)?,
	timeout: number?,
	yield: string?,
	promise: string?,
	inspectorOutput: string?, -- Where the packet inspector is written, when it is asked for
	shardSize: number?, -- The most entries one generated file holds
	profileLabels: boolean?, -- Whether the readers, the flush and the schema table carry MicroProfiler labels
	spans: { [string]: Span },
}

-- Instantiations are kept in the order references first name them, and Expand fills the list
export type File = { options: Options, declarations: { Declaration }, instantiations: { TypeDeclaration }? }

return {}
