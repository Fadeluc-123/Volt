--[[
    The limits, merged onto the runtime: what a packet must pass before
    any of it is decoded, which is its size, the player's packet rate
    and the handshake that opens a session; the rate each event and
    function allows a player; the failure every check reports, the
    handler that hears it and the one a runtime starts with; the counters
--]]

--!strict
--!native
local Limits = {}

local Config = require("./Config/Runtime")
local Hub = require("./Hub")
local Types = require("./Config/Types/Runtime")

type Bucket = Types.Bucket
type Failure = Types.Failure
type Joined = Types.Joined
type Limit = Types.Limit
type Message = Types.Message
type Runtime = Types.Runtime
type Stats = Types.Stats

local HANDSHAKE_BYTES: number = Config.handshakeBytes
local WARN_SECONDS: number = Config.warnSeconds

local HANDSHAKE_ID: number = 0 -- The one message id no schema uses, which opens a session

-- Takes one token from a bucket refilled at the rate a second and holding the burst at most, or finds none to take
local function take(bucket: Bucket, rate: number, burst: number, now: number): boolean
	local tokens: number = math.min(burst, bucket.tokens + (now - bucket.last) * rate)

	bucket.last = now

	if tokens < 1 then
		bucket.tokens = tokens
		return false
	end

	bucket.tokens = tokens - 1
	return true
end

-- One more failure of a kind in a set of counters
local function tally(stats: Stats, kind: string)
	stats.failures[kind] = (stats.failures[kind] or 0) + 1
end

-- Counters at zero, for a runtime or for one player
function Limits.fresh(): Stats
	return {
		packetsIn = 0,
		bytesIn = 0,
		messagesIn = 0,
		packetsOut = 0,
		bytesOut = 0,
		messagesOut = 0,
		rejected = 0,
		failures = {},
	}
end

-- The limit of every incoming message that has one, by id, which the wrapper may change while the game runs
function Limits.limits(self: Runtime, messages: { [number]: Message })
	local limits: { [number]: Limit } = self._limits
	for id: number, message: Message in messages do
		local rate: number? = message.rate
		if rate then
			limits[id] = { rate = rate, burst = rate }
		end
	end
end

--[[
    Writes the handshake as the first message of the client's first
    packet: the one id no schema uses, then the schema's hash, which the
    server checks against its own before it reads anything else
--]]

function Limits.handshake(self: Runtime, hash: number)
	local offset: number, out: buffer = self.reliable.begin(HANDSHAKE_BYTES)
	buffer.writeu8(out, offset, HANDSHAKE_ID)
	buffer.writeu32(out, offset + 1, hash)
end

--[[
    The checks a packet passes before any of it is decoded, on the
    server: it is from a player still here, no larger than maxPacket,
    within the player's packet rate, and after their handshake or is it.
    Accepting the handshake lets out what was held for them at the next
    flush, which then announces it; refusing it keeps them from being
    sent anything again. Returns where the loop starts, or nil for a
    packet that is dropped
--]]

function Limits.admit(self: Runtime, player: any, packet: buffer): number?
	local length: number = buffer.len(packet)
	local now: number = os.clock()
	local state: Joined? = self._players[player]

	self._now = now

	self:_count(player, "packetsIn", 1)
	self:_count(player, "bytesIn", length)

	-- The client hears from the server alone, whom it neither limits nor asks for a handshake
	if player == nil then
		return 0
	end

	if not state then
		self:fail(player, "packet", "from a player who has left")
		return nil
	end

	if length > self._maxPacket then
		self:fail(player, "packet", `{length} bytes, over maxPacket`)
		return nil
	end

	if not take(state.packets, self._maxPackets, self._maxPackets, now) then
		self:fail(player, "rate", `over {self._maxPackets} packets a second`)
		return nil
	end

	if state.handshaken then
		return 0
	end

	-- Nothing is read from a player before their handshake, which must open their first packet and is never retried
	if state.reliable.refused or length < HANDSHAKE_BYTES or buffer.readu8(packet, 0) ~= HANDSHAKE_ID then
		self:fail(player, "packet", "before the handshake")
		return nil
	end

	local hash: number = buffer.readu32(packet, 1)
	if hash ~= self._hash then
		-- What was held for them goes unsent, before the handler hears it and before any kick
		state.reliable.refused = true
		state.unreliable.refused = true

		self:fail(
			player,
			"handshake",
			string.format("Volt: schema mismatch (client 0x%08X, server 0x%08X)", hash, self._hash)
		)
		return nil
	end

	state.handshaken = true
	state.reliable.held = false
	state.unreliable.held = false

	-- Announced at the end of the next flush, once that flush has sent what was held and reported what it dropped
	table.insert(self._accepted, player)

	return HANDSHAKE_BYTES
end

--[[
    Whether a player is within an event's or a function's rate for one
    more message. A miss is a rate failure its caller reports, a call
    once its caller has been answered; the message was decoded, so the
    packet goes on without it
--]]

function Limits.allow(self: Runtime, player: any, id: number, limit: Limit): boolean
	local state: Joined? = self._players[player]
	if not state then
		return false
	end

	local buckets: { [number]: Bucket } = state.buckets
	local bucket: Bucket? = buckets[id]
	local now: number = self._now

	if not bucket then
		bucket = { tokens = limit.burst, last = now }
		buckets[id] = bucket
	end

	return take(bucket :: Bucket, limit.rate, limit.burst, now)
end

-- Reports a message past its rate, unless its player left part way through the packet, when it just goes
function Limits._limited(self: Runtime, player: any, name: string, limit: Limit)
	if self._players[player] then
		self:fail(player, "rate", `over {limit.rate} a second`, name)
	end
end

-- The counters of the runtime, or of one player, who has none when they are not here
function Limits.stats(self: Runtime, player: any): Stats
	if player == nil then
		return self._stats
	end

	local state: Joined? = self._players[player]
	return state and state.stats or self.fresh()
end

--[[
    Reports one failure: counted for the runtime and for the player it
    came from, then handed to the failure handler under pcall, so one
    that raises is warned about and goes no further. A message's name
    goes before a detail that does not already begin with it
--]]

function Limits.fail(self: Runtime, player: any, kind: string, detail: string, name: string?)
	local state: Joined? = self._players[player]

	if name and detail:sub(1, #name + 2) ~= `{name}: ` then
		detail = `{name}: {detail}`
	end

	tally(self._stats, kind)

	if state then
		tally(state.stats, kind)
	end

	local ok: boolean, raised: any = pcall(self._failure, player, kind, detail)
	if not ok then
		warn(`Volt: the failure handler raised: {raised}`)
	end
end

-- Replaces the failure handler for every kind and returns the one it replaced, the runtime's own the first time
function Limits.onFailure(self: Runtime, handler: Failure): Failure
	local replaced: Failure = self._failure
	self._failure = handler
	return replaced
end

-- Adds to one counter of the runtime and of the player it concerns
function Limits._count(self: Runtime, player: any, key: string, amount: number)
	local state: Joined? = self._players[player]
	-- Stats names each counter, so one named by a string is reached through the counters as a map
	local total: { [string]: number } = self._stats :: any

	total[key] += amount

	if state then
		local mine: { [string]: number } = state.stats :: any
		mine[key] += amount
	end
end

--[[
    The failure handler a runtime starts with: a handshake failure kicks
    the player with both hashes, a fire at a player who left is silent,
    and anything else warns, once a minute per kind and per player so an
    attack cannot flood the log while the counters stay exact. A bot is
    never kicked and its name never read, so it is warned about instead
--]]

function Limits._report(self: Runtime, player: any, kind: string, detail: string)
	if kind == "departed" then
		return
	end

	local bot: boolean = Hub.isBot(player)

	if kind == "handshake" and not bot then
		return player:Kick(detail)
	end

	local state: Joined? = self._players[player]
	local warned: { [string]: number } = state and state.warned or self._warned
	local last: number? = warned[kind]
	local now: number = os.clock()

	if last and now - last < WARN_SECONDS then
		return
	end

	warned[kind] = now

	local from: string = bot and " from a bot" or player and ` from {player.Name}` or ""
	warn(`Volt: {kind} failure{from}: {detail}`)
end

return Limits
