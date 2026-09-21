--[[
    The in-memory transport pair a test drives instead of the remotes: a
    server side, a client side per joined player, packets copied at fire
    time as the engine copies them and delivered on step, one Heartbeat
    per step, and a player list with join and leave
--]]

--!strict
local Mock = {} :: any
Mock.__index = Mock

local Types = require("./Config/Types/Runtime")

type Handler = Types.Handler
type Spawn = Types.Spawn
type Transport = Types.Transport

export type Player = { Name: string, UserId: number }

export type Mock = {
	server: Transport,
	players: { Player },
	join: (self: Mock, name: string) -> (Player, Transport),
	leave: (self: Mock, player: Player) -> (),
	step: (self: Mock) -> (),
}

type Packet = { player: any, packet: buffer, side: { any }? } -- Queued for the player it goes to, or came from

-- A buffer of its own, as the engine serialises a packet the moment it is fired
local function copy(packet: buffer): buffer
	local exact: buffer = buffer.create(buffer.len(packet))
	buffer.copy(exact, 0, packet)
	return exact
end

--[[
    A mock over the scheduler a test hands in, which is Lune's task.spawn
    under the test runner and the engine's in Studio
--]]

function Mock.new(spawn: Spawn): Mock
	local self = setmetatable({
		server = nil :: any,
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
	}, Mock)

	local function send(player: any, packet: buffer, side: { any }?)
		table.insert(self._toClient, { player = player, packet = copy(packet), side = side and table.clone(side) })
	end

	self.server = {
		reliable = send,
		unreliable = send,

		receive = function (handler: Handler)
			self._receive = handler
		end,

		heartbeat = function (callback: () -> ())
			table.insert(self._heartbeats, callback)
		end,

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
	}

	return self :: any
end

--[[
    A player joins: the server hears it, and the transport returned is
    that player's client side, so a client runtime can be started on it
--]]

function Mock:join(name: string): (Player, Transport)
	self._joined += 1

	local player: Player = { Name = name, UserId = self._joined }

	table.insert(self.players, player)
	self._present[player] = true

	for _, callback in self._added do
		callback(player)
	end

	local function send(_: any, packet: buffer, side: { any }?)
		table.insert(self._toServer, { player = player, packet = copy(packet), side = side and table.clone(side) })
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
function Mock:leave(player: Player)
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

function Mock:step()
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

	for _, callback in self._heartbeats do
		callback()
	end
end

return Mock
