--[[
    The nodes a parsed schema is made of, shared by every stage: the type
    forms, the declarations, the options and the file. Resolution fills
    path, target, references and the ids; the parser leaves them nil
--]]

--!strict
type Span = { start: number, finish: number }

export type Range = { min: number?, max: number?, start: number, finish: number }
export type Field = { name: string, type: Type, start: number, finish: number }
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

export type Type =
	{ kind: "primitive", name: string, range: Range?, start: number, finish: number }
	| Roblox
	| { kind: "struct", fields: { Field }, start: number, finish: number }
	| { kind: "enum", tag: string?, variants: { Variant }, start: number, finish: number }
	| { kind: "set", element: Type, range: Range?, start: number, finish: number }
	| { kind: "map", key: Type, value: Type, range: Range?, start: number, finish: number }
	| { kind: "array", element: Type, range: Range?, start: number, finish: number }
	| { kind: "optional", inner: Type, start: number, finish: number }
	| { kind: "union", members: { Type }, start: number, finish: number }
	| { kind: "reference", name: string, target: TypeDeclaration?, start: number, finish: number }

export type TypeDeclaration = {
	kind: "type",
	name: string,
	export: boolean,
	type: Type,
	path: string?,
	references: number?,
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
	spans: { [string]: Span },
	path: string?,
	toServer: number?,
	toClient: number?,
	start: number,
	finish: number,
}

export type Function = {
	kind: "function",
	name: string,
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

export type Declaration = TypeDeclaration | Event | Function | Namespace

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
	maxPacket: number?,
	maxPacketsPerSecond: number?,
	unreliableBudget: number?,
	queue: number?,
	rate: (number | string)?,
	functionRate: (number | string)?,
	timeout: number?,
	yield: string?,
	promise: string?,
	spans: { [string]: Span },
}

export type File = { options: Options, declarations: { Declaration } }

return {}
