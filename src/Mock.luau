--[[
    The in-memory transport pair a test drives instead of the remotes: a
    server side served through a hub of its own, a client side per joined
    player, packets copied at fire time and delivered on step, one
    Heartbeat per step, a player list with join, leave and a kick, and bots
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
}

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
	})

	self = setmetatable({
		server = server,
		players = {} :: { Player },
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
	}, Mock)

	return self
end

--[[
    A player joins: the server hears it, and the transport returned is
    that player's client side, so a client runtime can be started on it
--]]

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
		}
end

-- A player leaves: the server hears it while the player is still listed, as the engine orders it
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
end

--[[
    Delivers every packet queued in both directions to the handler on
    the other side, dropping one from or for a player who has left, then
    fires one Heartbeat on every runtime, where the flush happens
--]]

function Mock.step(self: Self)
	local toServer: { Packet }, toClient: { Packet } = self._toServer, self._toClient
	local receive: Handler? = self._receive

	self._toServer, self._toClient = {}, {}

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

-- A bot every runtime on the mock's server sets up as a player; the mock's own list, joins and leaves never see one
function Mock.addBot(self: Self, name: string): Bot
	return self._hub:add(name)
end

function Mock.removeBot(self: Self, bot: Bot)
	self._hub:remove(bot)
end

-- The bot's client side, whose packets reach the server in the same step and whose Heartbeat takes what it was sent
function Mock.connectBot(self: Self, bot: Bot): Transport
	return self._hub:connect(bot, SCOPE)
end

export type Mock = Self
type Self = typeof(setmetatable({} :: Fields, Mock))

return Mock
