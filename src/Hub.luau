--[[
    The hub every server transport of one VM is served through: the bots
    a harness adds, which every scope it serves takes as players, the
    packets between a bot's client sides and their scopes' servers, who
    is present, and one byte count per player for the whole VM
--]]

--!strict
local Hub = {} :: any
Hub.__index = Hub

local Traffic = require("./Traffic")
local Types = require("./Config/Types/Runtime")

type Bot = Types.Bot
type Fire = Types.Fire
type Handler = Types.Handler
type Record = Types.Record
type Spawn = Types.Spawn
type Transport = Types.Transport

type Callback = (player: any) -> ()
type Connect = (callback: () -> ()) -> () -> () -- Connects a callback to every frame and returns what disconnects it
type Packet = { packet: buffer, side: { any }? }

-- A scope the hub serves: its server runtime's receive, and the join and leave callbacks a bot is handed to
type Scope = { receive: Handler?, added: { Callback }, removing: { Callback } }

-- A bot's client side of a scope: its runtime's receive, what the server sent it, what waits for the server, its frames
type Side = { receive: Handler?, queue: { Packet }, waiting: { Packet }, disconnects: { () -> () } }

export type Hub = {
	serve: (self: Hub, scope: string, transport: Transport) -> Transport,
	add: (self: Hub, name: string) -> Bot,
	remove: (self: Hub, bot: Bot) -> (),
	connect: (self: Hub, bot: Bot, scope: string) -> Transport,
}

local BOT: {} = table.freeze({}) -- The metatable that marks a bot, which nothing else carries

-- A hub over the scheduler and the frame of its VM
function Hub.new(spawn: Spawn, heartbeat: Connect): Hub
	return setmetatable({
		_spawn = spawn,
		_heartbeat = heartbeat,
		_scopes = {} :: { [string]: Scope },
		_bots = {} :: { [Bot]: { [string]: Side } }, -- Every bot, with its client side of each scope a harness connected
		_record = Traffic.records(),
	}, Hub) :: any
end

-- Whether a value is a bot rather than a player
function Hub.isBot(value: any): boolean
	return getmetatable(value) == BOT
end

-- A buffer of its own, as the engine serialises a packet the moment it is fired
function Hub.copy(packet: buffer): buffer
	local exact: buffer = buffer.create(buffer.len(packet))
	buffer.copy(exact, 0, packet)
	return exact
end

--[[
    Serves a scope's server transport: the players it lists and the joins
    and leaves it signals take in the hub's bots, a fire at a bot goes to
    the bot's client side of the scope, or nowhere when no harness
    connected one, and presence and the byte count answer for both
--]]

function Hub:serve(name: string, transport: Transport): Transport
	local scope: Scope = self:_scope(name)
	local bots: { [Bot]: { [string]: Side } } = self._bots

	local players = transport.players :: () -> { any }
	local added = transport.playerAdded :: (callback: Callback) -> ()
	local removing = transport.playerRemoving :: (callback: Callback) -> ()
	local present = transport.present :: (player: any) -> boolean

	-- A packet for a bot waits for its client's next frame, since no remote reaches a bot
	local function fire(remote: Fire): Fire
		return function (target: any, packet: buffer, side: { any }?)
			local sides: { [string]: Side }? = bots[target]
			if not sides then
				return remote(target, packet, side)
			end

			local client: Side? = sides[name]
			if client then
				table.insert(client.queue, { packet = packet, side = side })
			end
		end
	end

	return {
		reliable = fire(transport.reliable),
		unreliable = fire(transport.unreliable),

		receive = function (handler: Handler)
			scope.receive = handler
			transport.receive(handler)
		end,

		heartbeat = transport.heartbeat,
		spawn = transport.spawn,

		players = function (): { any }
			local list: { any } = players()
			for bot: Bot in bots do
				table.insert(list, bot)
			end
			return list
		end,

		playerAdded = function (callback: Callback)
			table.insert(scope.added, callback)
			added(callback)
		end,

		playerRemoving = function (callback: Callback)
			table.insert(scope.removing, callback)
			removing(callback)
		end,

		present = function (player: any): boolean
			return bots[player] ~= nil or present(player)
		end,

		traffic = self._record,
	}
end

-- Adds a bot, which every scope served now joins at once and every scope served later lists among its players
function Hub:add(name: string): Bot
	local bot: Bot = table.freeze(setmetatable({ Name = name }, BOT)) :: any

	self._bots[bot] = {}

	for _, scope: Scope in self._scopes do
		for _, callback: Callback in scope.added do
			callback(bot)
		end
	end

	return bot
end

--[[
    Takes a bot away: every scope's leave runs while it is still present,
    then its client sides stop, their frames disconnected and anything
    queued for them or by them dropped
--]]

function Hub:remove(bot: Bot)
	local sides: { [string]: Side }? = self._bots[bot]
	if not sides then
		return
	end

	for _, scope: Scope in self._scopes do
		for _, callback: Callback in scope.removing do
			callback(bot)
		end
	end

	self._bots[bot] = nil

	for _, side: Side in sides do
		for _, disconnect: () -> () in side.disconnects do
			disconnect()
		end

		table.clear(side.queue)
		table.clear(side.waiting)
		
		side.receive = nil
	end
end

--[[
    A bot's client side of one scope, which a harness starts a client
    runtime on: its fires reach the scope's server in the same frame,
    copied as the engine copies them, or wait for the frame after that
    server starts, and each of its frames first hands it what the server
    sent since the last; a bot connects to a scope once
--]]

function Hub:connect(bot: Bot, name: string): Transport
	local sides: { [string]: Side }? = self._bots[bot]
	assert(sides, "Volt: connected a bot this hub does not have")
	assert(sides[name] == nil, `Volt: connected a bot to {name} a second time`)

	local scope: Scope = self:_scope(name)
	local side: Side = { receive = nil, queue = {}, waiting = {}, disconnects = {} }

	sides[name] = side

	-- A packet waits while the scope has no server to hear it, and behind any that waited, as a remote keeps its events
	local function send(_: any, packet: buffer, slots: { any }?)
		local copy: buffer, copied: { any }? = Hub.copy(packet), slots and table.clone(slots)
		local receive: Handler? = scope.receive

		if receive and not side.waiting[1] then
			receive(bot, copy, copied)
		else
			table.insert(side.waiting, { packet = copy, side = copied })
		end
	end

	-- Each frame of the bot's runtime first hands the server what waited for it, then the bot what the server sent
	local function heartbeat(callback: () -> ())
		local disconnect: () -> () = self._heartbeat(function ()
			local queue: { Packet } = side.queue
			local waiting: { Packet } = side.waiting
			local receive: Handler? = side.receive
			local server: Handler? = scope.receive

			-- What waited goes at a frame, never as the server connects, since its module has no runtime until start returns
			if server and waiting[1] then
				side.waiting = {}
				for _, held: Packet in waiting do
					server(bot, held.packet, held.side)
				end
			end

			-- A packet the server sends while these are handed over waits for the next frame
			if receive and queue[1] then
				side.queue = {}
				for _, queued: Packet in queue do
					receive(nil, queued.packet, queued.side)
				end
			end

			callback()
		end)

		table.insert(side.disconnects, disconnect)
	end

	return {
		reliable = send,
		unreliable = send,

		receive = function (handler: Handler)
			side.receive = handler
		end,

		heartbeat = heartbeat,
		spawn = self._spawn,
	}
end

-- A scope's record, made the first time a transport is served for it or a bot is connected to it
function Hub:_scope(name: string): Scope
	local scope: Scope? = self._scopes[name]
	if scope then
		return scope
	end

	local made: Scope = { receive = nil, added = {}, removing = {} }
	self._scopes[name] = made

	return made
end

return Hub
