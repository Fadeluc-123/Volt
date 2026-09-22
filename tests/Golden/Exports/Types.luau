--[[
    The types module Volt 0.1.0 generated from Exports.volt: every named type of
    the schema and the handle types the generated API's entries fit, for
    code shared between the client and the server. Generated code: change
    the schema and run volt again rather than editing this file
--]]

--!strict
export type Save = { version: number, names: { string }, owner: Instance? }
export type Inventory_Kind = "Bag" | "Chest"

export type ServerEvent<A...> = {
	fire: (player: Player, A...) -> (),
	fireAll: (A...) -> (),
	fireList: (players: { Player }, A...) -> (),
	fireExcept: (player: Player, A...) -> (),
	fireSet: (players: { [Player]: true }, A...) -> (),
}

export type ServerListener<A...> = {
	on: (listener: (player: Player, A...) -> ()) -> () -> (),
	iter: () -> () -> (number, Player, A...),
}

export type ServerFunction<A..., R...> = { on: (handler: (player: Player, A...) -> R...) -> () -> () }

export type ClientEvent<A...> = { fire: (A...) -> () }

export type ClientListener<A...> = {
	on: (listener: (A...) -> ()) -> () -> (),
	iter: () -> () -> (number, A...),
}

export type ClientFunction<A..., R...> = { invoke: (A...) -> (boolean, R...) }

export type ClientPromise<A...> = { invoke: (A...) -> any }

export type Exported<T> = {
	write: (value: T) -> (buffer, { any }?),
	read: (packet: buffer, side: { any }?) -> T,
}

return {}
