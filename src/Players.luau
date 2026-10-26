--[[
    The player lifecycle on the server, merged onto the runtime: the
    states, counters and buckets each player or bot gets and loses, the
    target a fire writes into, the callbacks a game or a package hears
    joins, leaves and handshakes on, and each player's byte count
--]]

--!strict
local Players = {} :: any

local Hub = require("./Hub")
local Limits = require("./Limits")
local Send = require("./Send")
local Traffic = require("./Traffic")
local Types = require("./Config/Types/Runtime")

type Bucket = Types.Bucket
type Record = Types.Record
type State = Send.State
type Stats = Types.Stats

type Callback = (player: any) -> ()

-- What the server keeps per player: their send states, counters and rate buckets, whether they have handshaken
type Player = {
	reliable: State,
	unreliable: State,
	stats: Stats,
	packets: Bucket,
	buckets: { [number]: Bucket },
	handshaken: boolean,
	warned: { [string]: number },
}

-- Keeps a callback under a token of its own and returns the closure that takes it out again
local function subscribe(bucket: { [{}]: Callback }, callback: Callback): () -> ()
	local token: {} = {}
	bucket[token] = callback

	-- Cleanup and disconnect from callback
	return function ()
		bucket[token] = nil
	end
end

Players.isBot = Hub.isBot -- A plain function, since the generated API hands it out as a value

--[[
    Points both sends at a player's states before a fire writes, or at
    the scratch states when no player is given, which is where a
    broadcast is written before it is copied. A player the transport
    lists whom this runtime has not set up yet, because a game's own join
    callback ran first, is set up here. False for a player who has left
    or whose handshake failed, so the fire writes nothing for them
--]]

function Players:target(player: any): boolean
	if player == nil then
		self.reliable.current = self.reliable.scratch
		self.unreliable.current = self.unreliable.scratch
		return true
	end

	local states: Player? = self._players[player]
	local present: ((player: any) -> boolean)? = self._present

	if not states and present and present(player) then
		self:_join(player)
		states = self._players[player]
	end

	if not states then
		self:fail(player, "departed", "fired at a player who has left")
		return false
	end

	if states.reliable.refused then
		self:fail(player, "departed", "fired at a player whose handshake failed")
		return false
	end

	self.reliable.current = states.reliable
	self.unreliable.current = states.unreliable

	return true
end

--[[
    Calls back once a player or bot is set up, at once for every one
    already set up and then for each who joins; each callback runs on
    the transport's scheduler and the closure returned disconnects it
--]]

function Players:onJoin(callback: Callback): () -> ()
	local present: { [any]: Player } = table.clone(self._players) -- Who is here now, before a callback can add to it
	local disconnect: () -> () = subscribe(self._joins, callback)

	for player: any in present do
		self._spawn(callback, player)
	end

	return disconnect
end

-- Calls back as a player or bot leaves, before their states and counters go
function Players:onLeave(callback: Callback): () -> ()
	return subscribe(self._leaves, callback)
end

-- Calls back when a player's or bot's handshake is accepted, which is when what was held for them goes out
function Players:onHandshake(callback: Callback): () -> ()
	return subscribe(self._handshakes, callback)
end

--[[
    The bytes sent to a player over the last second, then the bytes
    written for them and not yet flushed, across every runtime the VM's
    hub serves, or this runtime alone on a transport without one
--]]

function Players:traffic(player: any): (number, number)
	return Traffic.read(self._record(player))
end

-- States for a player who joined, with their packet bucket full on arrival; one known or let go keeps what they have
function Players:_join(player: any)
	if self._players[player] or self._left[player] then
		return
	end

	local stats: Stats = Limits.fresh()
	local record: Record = self._record(player)
	local held: boolean = not Hub.isBot(player) -- A bot has no client that could miss what is sent before it loads

	self._players[player] = {
		reliable = self.reliable:add(player, stats, record, held),
		unreliable = self.unreliable:add(player, stats, record, held),
		stats = stats,
		packets = { tokens = self._maxPackets, last = os.clock() },
		buckets = {}, -- One per event and function the player has sent, by id
		handshaken = false,
		warned = {}, -- When the runtime's own handler last warned of each kind about this player
	}

	self:_announce(self._joins, player)
end

-- Frees a player's states once the callbacks have heard it, and never sets them up again, so a late fire recreates nothing
function Players:_leave(player: any)
	self._left[player] = true

	if not self._players[player] then
		return
	end

	self:_announce(self._leaves, player)

	self._players[player] = nil
	self.reliable:remove(player)
	self.unreliable:remove(player)
end

-- Runs every callback of a bucket for a player, each on the transport's scheduler so one that yields holds up nothing
function Players:_announce(bucket: { [{}]: Callback }, player: any)
	-- A copy, so a callback that subscribes or disconnects leaves the list this announce walks as it was
	for _, callback: Callback in table.clone(bucket) do
		self._spawn(callback, player)
	end
end

return Players
