--[[
    The player lifecycle on the server, merged onto the runtime: the
    states, counters and buckets each player or bot gets and loses, the
    target a fire or a call writes into, the callbacks a game or a package
    hears joins, leaves and handshakes on, and each player's byte count
--]]

--!strict
local Players = {}

local Hub = require("./Hub")
local Limits = require("./Limits")
local Traffic = require("./Traffic")
local Types = require("./Config/Types/Runtime")

type Callback = Types.Callback
type Joined = Types.Joined
type Record = Types.Record
type Runtime = Types.Runtime
type Send = Types.Send
type State = Types.State
type Stats = Types.Stats

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
    Points both sends at a player's states before a fire or a call
    writes, and given a channel's number, that channel's send at theirs.
    A player the transport lists whom this runtime has not set up yet,
    because a game's own join callback ran first, is set up here. False
    for a player who has left or whose handshake failed, so nothing is
    written for them; no player at all is the caller's bug, and raises
--]]

function Players.target(self: Runtime, player: any, stream: number?): boolean
	assert(player ~= nil, "Volt: a message for one player was sent to none")

	local states: Joined? = self._players[player]
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

	if stream then
		self.streams[stream].current = states.streams[stream]
	end

	return true
end

--[[
    Calls back once a player or bot is set up, at once for every one
    already set up and then for each who joins; each callback runs on
    the transport's scheduler and the closure returned disconnects it
--]]

function Players.onJoin(self: Runtime, callback: Callback): () -> ()
	local present: { [any]: Joined } = table.clone(self._players) -- Who is here now, before a callback can add to it
	local disconnect: () -> () = subscribe(self._joins, callback)

	for player: any in present do
		self._spawn(callback, player)
	end

	return disconnect
end

-- Calls back as a player or bot leaves, before their states and counters go
function Players.onLeave(self: Runtime, callback: Callback): () -> ()
	return subscribe(self._leaves, callback)
end

--[[
    Calls back once a player's or bot's handshake is accepted, at the end
    of the first flush after it, which has sent what was held for them
    and reported what it dropped; the closure returned disconnects it
--]]

function Players.onHandshake(self: Runtime, callback: Callback): () -> ()
	return subscribe(self._handshakes, callback)
end

--[[
    The bytes sent to a player over the last second, then the bytes
    written for them and not yet flushed, across every runtime the VM's
    hub serves, or this runtime alone on a transport without one
--]]

function Players.traffic(self: Runtime, player: any): (number, number)
	return Traffic.read(self._record(player))
end

-- States for a player who joined, with their packet bucket full on arrival; one known or let go keeps what they have
function Players._join(self: Runtime, player: any)
	if self._players[player] or self._left[player] then
		return
	end

	local stats: Stats = Limits.fresh()
	local record: Record = self._record(player)
	local held: boolean = not Hub.isBot(player) -- A bot has no client that could miss what is sent before it loads
	local streams: { State } = {}

	-- A state in each channel's send too, counted and held with the default one
	for channel: number, stream: Send in self.streams do
		streams[channel] = stream:add(player, stats, record, held)
	end

	self._players[player] = {
		reliable = self.reliable:add(player, stats, record, held),
		unreliable = self.unreliable:add(player, stats, record, held),
		streams = streams,
		stats = stats,
		packets = { tokens = self._maxPackets, last = os.clock() },
		buckets = {}, -- One per event and function the player has sent, by id
		sequences = {}, -- The last sequence taken from them of each ordered event, by id
		handshaken = false,
		warned = {}, -- When the runtime's own handler last warned of each kind about this player
		calls = {}, -- The calls the server has in flight to them, a slot table per function opened at its first
		known = 0, -- The dictionary entries they hold, so a joiner's first packet follows all of them
	}

	self:_announce(self._joins, player)
end

--[[
    Frees a player's states once the callbacks have heard it, then fails
    the calls the server has in flight to them, and never sets them up
    again, so a late fire or call recreates nothing
--]]

function Players._leave(self: Runtime, player: any)
	local state: Joined? = self._players[player]

	self._left[player] = true

	if not state then
		return
	end

	self:_announce(self._leaves, player)

	self._players[player] = nil
	self.reliable:remove(player)
	self.unreliable:remove(player)

	for _, stream: Send in self.streams do
		stream:remove(player)
	end

	self:_abandon(state)
end

--[[
    Sets up each player listed or set whom the transport lists and this
    runtime has not set up yet, as a fire at them does, so a broadcast
    naming a joiner from any callback reaches them
--]]

function Players._setUp(self: Runtime, targets: { [any]: any }?)
	local present: ((player: any) -> boolean)? = self._present
	if not targets or not present then
		return
	end

	-- A list carries its players as values and a set as keys
	for key: any, value: any in targets do
		local player: any = typeof(key) == "number" and value or key

		if not self._players[player] and present(player) then
			self:_join(player)
		end
	end
end

-- Runs every callback of a bucket for a player, each on the transport's scheduler so one that yields holds up nothing
function Players._announce(self: Runtime, bucket: { [{}]: Callback }, player: any)
	-- A copy, so a callback that subscribes or disconnects leaves the list this announce walks as it was
	for _, callback: Callback in table.clone(bucket) do
		self._spawn(callback, player)
	end
end

return Players
