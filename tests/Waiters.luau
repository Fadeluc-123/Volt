--[[
    What the tests of the client's waits run over: a client runtime on a
    mock with three events read by hand as generated readers read them,
    what its listeners heard and what it reported, an instance as a test
    makes one, and the packets the server's side sends it by hand
--]]

--!strict
local task = require("@lune/task")

local packet = require("./Packet")
local Volt = require("@volt")
local Config = require("@volt/Config/Runtime")

type Mock = Volt.Mock
type Runtime = Volt.Runtime
type Schema = Volt.Schema
type Transport = Volt.Transport

export type Report = { player: any, kind: string, detail: string } -- One failure the client reported
export type Settings = { mode: string?, timeout: number?, stamp: boolean? } -- How the awaited events are delivered and wait

-- A client runtime with what its listeners heard, one line per message, and what it reported
export type Client = { runtime: Runtime, seen: { string }, failures: { Report } }

-- A client on Alice's side of a mock, and the server's transport, which gives each instance its id
export type Harness = Client & { mock: Mock, alice: any, reference: (instance: any) -> number }

local STAMP_BYTES: number = Config.stampBytes

-- The options the runtime reads, at the compiler's defaults
local OPTIONS: { [string]: any } = {
	flush = 1,
	manualReplication = false,
	maxPacket = 8192,
	maxPacketsPerSecond = 240,
	maxOutgoing = 262144,
	unreliableBudget = 900,
}

local Waiters = {
	spawned = 1, -- An awaited model's id and a byte of health, then an instance in the side array
	plain = 2, -- One byte, naming no instance
	pair = 3, -- Two awaited instances' ids, of any class
}

-- An instance as a test makes one, which the runtime only ever hands on
function Waiters.instance(name: string, class: string?): any
	return { Name = name, ClassName = class or "Model" }
end

-- A schema table with the messages given on one side
function Waiters.schema(side: string, messages: { [number]: any }, stamp: boolean?): Schema
	return {
		version = Volt.version,
		hash = 0,
		scope = "Test",
		side = side,
		idBytes = 1,
		stamp = stamp,
		options = OPTIONS,
		messages = messages,
		outgoing = {},
	}
end

-- A packet whose bytes follow the server time it was stamped with, as a stamped server sends one
function Waiters.stamped(time: number, bytes: { number }): buffer
	local body: buffer = packet(bytes)
	local out: buffer = buffer.create(STAMP_BYTES + buffer.len(body))

	buffer.writef64(out, 0, time)
	buffer.copy(out, STAMP_BYTES, body)

	return out
end

--[[
    Starts a client runtime on a transport with the three events, each
    read by hand as a generated reader would read it: every id looked up
    as it is read, a class checked only once its instance has arrived,
    and the tail handing the values to await, which delivers or waits
--]]

function Waiters.start(transport: Transport, settings: Settings): Client
	local seen: { string } = {}
	local failures: { Report } = {}
	local client: Runtime
	local mode: string = settings.mode or "ManySync"
	local timeout: number = settings.timeout or 10

	local function readSpawned(_: any, from: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
		local start: number, sideStart: number = cursor, sideCursor

		if cursor + 5 > length then
			error("World.Spawned: truncated")
		end

		local model: any = client.instanceById(buffer.readu32(from, cursor))
		if model and model.ClassName ~= "Model" then
			error("World.Spawned.model: expected AwaitedInstance(Model)")
		end

		local health: number = buffer.readu8(from, cursor + 4)
		if health == 0 then
			error("World.Spawned.health: out of range")
		end

		local by: any = side[sideCursor]
		cursor += 5
		sideCursor += 1

		return client:await(Waiters.spawned, from, start, cursor, side, sideStart, sideCursor, model, health, by)
	end

	local function readPlain(_: any, from: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
		if cursor + 1 > length then
			error("World.Plain: truncated")
		end

		return client:deliver(Waiters.plain, nil, cursor + 1, sideCursor, buffer.readu8(from, cursor))
	end

	local function readPair(_: any, from: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
		local start: number, sideStart: number = cursor, sideCursor

		if cursor + 8 > length then
			error("World.Pair: truncated")
		end

		local first: any = client.instanceById(buffer.readu32(from, cursor))
		local second: any = client.instanceById(buffer.readu32(from, cursor + 4))
		cursor += 8

		return client:await(Waiters.pair, from, start, cursor, side, sideStart, sideCursor, first, second)
	end

	-- The client rows: only an event that reaches an awaited instance carries a timeout
	local messages: { [number]: any } = {
		[Waiters.spawned] = {
			name = "World.Spawned",
			kind = "event",
			mode = mode,
			queue = 64,
			timeout = timeout,
			read = readSpawned,
		},

		[Waiters.plain] = { name = "World.Plain", kind = "event", mode = "ManySync", queue = 64, read = readPlain },

		[Waiters.pair] = {
			name = "World.Pair",
			kind = "event",
			mode = "ManySync",
			queue = 64,
			timeout = timeout,
			read = readPair,
		},
	}

	client = Volt.start(Waiters.schema("client", messages, settings.stamp), transport)

	client:onFailure(function (player: any, kind: string, detail: string)
		table.insert(failures, { player = player, kind = kind, detail = detail })
	end)

	-- A polled event has no listener; the others say what they heard, and on a stamped client when it was sent
	local function at(): string
		return settings.stamp and ` at {client:serverTime()}` or ""
	end

	if mode ~= "Polling" then
		client:on(Waiters.spawned, function (model: any, health: number, by: any)
			local slot: string = by and ` by {by}` or ""
			table.insert(seen, `{model.Name} {health}{slot}{at()}`)
		end)
	end

	client:on(Waiters.plain, function (value: number)
		table.insert(seen, `plain {value}{at()}`)
	end)

	client:on(Waiters.pair, function (first: any, second: any)
		table.insert(seen, `{first.Name} {second.Name}`)
	end)

	return { runtime = client, seen = seen, failures = failures }
end

-- Alice's client over a mock of its own, with the server's transport left to the test to send through by hand
function Waiters.setup(settings: Settings?): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local alice: any, transport: Transport = mock:join("Alice")
	local client: Client = Waiters.start(transport, settings or {})

	return {
		runtime = client.runtime,
		seen = client.seen,
		failures = client.failures,
		mock = mock,
		alice = alice,
		reference = assert(mock.server.reference, "the mock's server gives instances ids"),
	}
end

-- Sends Alice one packet from the server, its side array with it, and delivers it
function Waiters.send(harness: Harness, sent: buffer, side: { any }?)
	harness.mock.server.reliable(harness.alice, sent, side)
	harness.mock:step()
end

return Waiters
