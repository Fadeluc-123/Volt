--[[
    The in-memory transport pair a test drives instead of the remotes: a
    server side, a client side per joined player, bots, the server's clock
    and instance ids a test can hide from the clients
--]]

--!strict
local Mock = {}
Mock.__index = Mock

local Hub = require("./Hub")
local Types = require("./Config/Types/Runtime")

type Bot = Types.Bot
type Handler = Types.Handler
type Hub = Hub.Hub
type Spawn = Types.Spawn
type Transport = Types.Transport

export type Player = {
	Name: string,
	UserId: number,
	Kick: (self: Player, message: string) -> (),
	kicked: string?, -- The message the player was kicked with, once they have been
}

type Packet = { player: any, packet: buffer, side: { any }? } -- Queued for the player it goes to, or came from

type Fields = {
	server: Transport,
	players: { Player },
	time: number,
	_spawn: Spawn,
	_present: { [Player]: boolean },
	_toServer: { Packet },
	_toClient: { Packet },
	_receive: Handler?,
	_clients: { [Player]: Handler },
	_heartbeats: { () -> () },
	_added: { (player: any) -> () },
	_removing: { (player: any) -> () },
	_joined: number,
	_hub: Hub,
	_ids: { [any]: number },
	_instances: { any },
	_hidden: { [any]: boolean },
	_revealed: { any },
	_resolved: { [Player]: (id: number) -> () },
}

--- @class Mock
--- An in-memory transport pair a test drives in place of the remotes, made
--- by `Volt.mock`. `server` is the server's transport, `join` hands out a
--- client transport per player, and `Volt.start` runs a runtime over
--- either. Nothing moves until `step`: a packet between the server and a
--- player is copied when it is fired, as the engine copies it, and waits in
--- one ordered, lossless queue per direction until the next step delivers
--- it and fires one Heartbeat on every runtime. A mock serves one scope, so
--- two Volt scopes never share one

--- @prop server Transport
--- @within Mock
--- The server's transport, which a test hands to `Volt.start` in place of
--- the remotes. A second server runtime started on it replaces the first's
--- receive

--- @prop players { Player }
--- @within Mock
--- Every player who has joined and not yet left, in the order they joined.
--- Each is a plain, unfrozen table standing in for a Player, with `Name`,
--- `UserId` counting up from 1, `Kick` and `kicked`. A bot is never listed

--- @prop time number
--- @within Mock
--- The server's clock, 0 until a test sets it. The server transport's `now`
--- returns it, so a test sets it to stamp what the server sends under
--- `option stamp`

local SCOPE: string = "Mock" -- The one scope a mock's hub serves, since two scopes cannot share a mock

--[[
    A mock over the scheduler a test hands in, which is Lune's task.spawn
    under the test runner and the engine's in Studio
--]]

function Mock.new(spawn: Spawn): Self
	local self: Self -- The mock, which the transport's closures below reach once it is made

	local function send(player: any, packet: buffer, side: { any }?)
		table.insert(self._toClient, { player = player, packet = Hub.copy(packet), side = side and table.clone(side) })
	end

	-- Fires every step, until the closure returned takes the callback out again
	local function connect(callback: () -> ()): () -> ()
		table.insert(self._heartbeats, callback)

		return function ()
			local index: number? = table.find(self._heartbeats, callback)
			if index then
				table.remove(self._heartbeats, index)
			end
		end
	end

	-- The server transport's frame, which keeps its callback for as long as the mock lives
	local function heartbeat(callback: () -> ())
		connect(callback)
	end

	local hub: Hub = Hub.new(spawn, connect) -- What the server is served through, and what a bot is added by
	local server: Transport = hub:serve(SCOPE, {
		reliable = send,
		unreliable = send,

		receive = function (handler: Handler)
			self._receive = handler
		end,

		heartbeat = heartbeat,
		spawn = spawn,

		players = function (): { any }
			return table.clone(self.players)
		end,

		playerAdded = function (callback: (player: any) -> ())
			table.insert(self._added, callback)
		end,

		playerRemoving = function (callback: (player: any) -> ())
			table.insert(self._removing, callback)
		end,

		present = function (player: any): boolean
			return self._present[player] == true
		end,

		-- The server's clock is whatever the test set
		now = function (): number
			return self.time
		end,

		-- An instance's id is the next one the first time a message names it, then the same while the mock lives
		reference = function (instance: any): number
			local id: number? = self._ids[instance]
			if id then
				return id
			end

			table.insert(self._instances, instance)
			self._ids[instance] = #self._instances

			return #self._instances
		end,
	})

	self = setmetatable({
		server = server,
		players = {} :: { Player },
		time = 0,
		_spawn = spawn,
		_present = {} :: { [Player]: boolean },
		_toServer = {} :: { Packet },
		_toClient = {} :: { Packet },
		_receive = nil :: Handler?, -- The server runtime's handler
		_clients = {} :: { [Player]: Handler }, -- Each client runtime's handler, by its player
		_heartbeats = {} :: { () -> () },
		_added = {} :: { (player: any) -> () },
		_removing = {} :: { (player: any) -> () },
		_joined = 0, -- Players so far, which numbers the next one
		_hub = hub,
		_ids = {} :: { [any]: number }, -- The id the server gave each instance it named
		_instances = {} :: { any }, -- Each id's instance, the ids numbered from 1 in the order they were given
		_hidden = {} :: { [any]: boolean }, -- The instances no client sees, as if they had not streamed in
		_revealed = {} :: { any }, -- The instances revealed since the last step, whose ids the clients hear at the next
		_resolved = {} :: { [Player]: (id: number) -> () }, -- What each client runtime hears an arrival on, by its player
	}, Mock)

	return self
end

--- A player joins: the server's join callbacks run at once, in the order
--- they were registered, before this returns. The player's `Kick` keeps
--- its message in `kicked` and makes the player leave, as the engine's
--- does. Each player has a client transport of their own, so any number of
--- client runtimes can run on one mock
--- @method join
--- @within Mock
--- @param name string -- The player's `Name`
--- @return Player -- The new player, now in `players`
--- @return Transport -- The player's client side, on which a test starts a client runtime

function Mock.join(self: Self, name: string): (Player, Transport)
	self._joined += 1

	local player: Player = {
		Name = name,
		UserId = self._joined,
		kicked = nil,

		-- Kicked as the engine does it: the message kept, and the player gone
		Kick = function (who: Player, message: string)
			who.kicked = message
			self:leave(who)
		end,
	}

	table.insert(self.players, player)
	self._present[player] = true

	for _, callback in self._added do
		callback(player)
	end

	local function send(_: any, packet: buffer, side: { any }?)
		table.insert(self._toServer, { player = player, packet = Hub.copy(packet), side = side and table.clone(side) })
	end

	return player,
		{
			reliable = send,
			unreliable = send,

			receive = function (handler: Handler)
				self._clients[player] = handler
			end,

			heartbeat = function (callback: () -> ())
				table.insert(self._heartbeats, callback)
			end,

			spawn = self._spawn,

			-- Every instance the server named is here at once, unless a test hid it
			resolve = function (id: number): any
				local instance: any = self._instances[id]
				if self._hidden[instance] then
					return nil
				end

				return instance
			end,

			resolved = function (callback: (id: number) -> ())
				self._resolved[player] = callback
			end,
		}
end

--- A player leaves: the server's leave callbacks run at once, in the order
--- they were registered, while the player is still in `players`, as the
--- engine orders it. Then the mock forgets them, and a packet queued from
--- or for them is dropped at the next step
--- @method leave
--- @within Mock
--- @param player Player -- A player `join` returned

function Mock.leave(self: Self, player: Player)
	for _, callback in self._removing do
		callback(player)
	end

	local index: number? = table.find(self.players, player)
	if index then
		table.remove(self.players, index)
	end

	self._present[player] = nil
	self._clients[player] = nil
	self._resolved[player] = nil
end

--- Moves the mock forward one frame. First every client hears the id of
--- each instance revealed since the last step, if the server has named it
--- and it is still visible. Then every packet queued in both directions
--- reaches the handler on the other side, those bound for the server
--- first, and one from or for a player who has left, or for a player with
--- no client runtime, is dropped. Last, one Heartbeat fires on every
--- runtime in the order they connected, which is when each one sends, so
--- with `flush = 1` a fire made outside `step` arrives at the second step
--- @method step
--- @within Mock

function Mock.step(self: Self)
	local toServer: { Packet }, toClient: { Packet } = self._toServer, self._toClient
	local receive: Handler? = self._receive
	local revealed: { any } = self._revealed

	self._toServer, self._toClient, self._revealed = {}, {}, {}

	for _, instance: any in revealed do
		local id: number? = self._ids[instance]

		if id and not self._hidden[instance] then
			for _, player: Player in table.clone(self.players) do
				local resolved: ((id: number) -> ())? = self._resolved[player]
				if resolved then
					resolved(id)
				end
			end
		end
	end

	for _, queued: Packet in toServer do
		if receive and self._present[queued.player] then
			receive(queued.player, queued.packet, queued.side)
		end
	end

	for _, queued: Packet in toClient do
		local handler: Handler? = self._clients[queued.player]
		if handler then
			handler(nil, queued.packet, queued.side)
		end
	end

	local heartbeats: { () -> () } = self._heartbeats

	-- A copy, so a Heartbeat that disconnects one skips no other, and one disconnected before its turn does not fire
	for _, callback: () -> () in table.clone(heartbeats) do
		if table.find(heartbeats, callback) then
			callback()
		end
	end
end

--- Makes an instance invisible to every player's client, as if it had not
--- streamed in, so a message naming it as an `AwaitedInstance` waits. A
--- bot still sees it
--- @method hide
--- @within Mock
--- @param instance any -- The instance to hide

function Mock.hide(self: Self, instance: any)
	self._hidden[instance] = true
end

--- Makes a hidden instance visible again. Each client hears its id arrive
--- at the start of the next step, before that step's packets
--- @method reveal
--- @within Mock
--- @param instance any -- The instance to show again

function Mock.reveal(self: Self, instance: any)
	self._hidden[instance] = nil
	table.insert(self._revealed, instance)
end

--- Adds a bot, which every server runtime on `server` sets up as a
--- player, one started later included. A bot is never in `players`, and
--- `join` and `leave` never see one
--- @method addBot
--- @within Mock
--- @param name string -- The bot's `Name`
--- @return Bot -- The bot, a frozen table with a `Name` and no `UserId` or `Kick`

function Mock.addBot(self: Self, name: string): Bot
	return self._hub:add(name)
end

--- Takes a bot away: the server's leave callbacks run while it is still
--- present, then its client side stops, its Heartbeats disconnected and
--- every packet queued for it or by it dropped
--- @method removeBot
--- @within Mock
--- @param bot Bot -- A bot `addBot` returned

function Mock.removeBot(self: Self, bot: Bot)
	self._hub:remove(bot)
end

--- The bot's client side. Its packets reach the server in the same step,
--- or at its first frame after the server runtime starts when sent before
--- it, and each of its frames first takes what the server sent it. A bot
--- connects once, and connecting it again, or after it was removed, errors
--- @method connectBot
--- @within Mock
--- @param bot Bot -- A bot `addBot` returned
--- @return Transport -- The bot's client side, on which a test starts a client runtime

function Mock.connectBot(self: Self, bot: Bot): Transport
	return self._hub:connect(bot, SCOPE)
end

export type Mock = Self
type Self = typeof(setmetatable({} :: Fields, Mock))

return Mock
