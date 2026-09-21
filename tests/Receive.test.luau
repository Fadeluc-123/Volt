--[[
    Proves the receive side: the loop over a packet's messages, what a
    bad packet or a bad message drops and reports, delivery by call mode
    with the player first on the server and absent on the client, the
    sync listener's error and yield reports, the queue before the first
    listener and the poll that drains it
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock
type Runtime = Volt.Runtime
type Spawn = Volt.Spawn
type Transport = Volt.Transport

type Report = { kind: string, detail: string } -- One failure the runtime reported

-- A runtime on one side of a mock, with what its listeners saw and what it reported
type Harness = {
	runtime: Runtime,
	mock: Mock,
	isServer: boolean,
	player: any,
	client: Transport, -- The joined player's client transport, which is the far end of a server harness
	seen: { string },
	failures: { Report },
}

local PING: number = 1 -- The one event's id

-- A packet of ping messages, one byte of value each
local function pings(...: number): buffer
	local count: number = select("#", ...)
	local packet: buffer = buffer.create(count * 2)

	for index = 1, count do
		buffer.writeu8(packet, index * 2 - 2, PING)
		buffer.writeu8(packet, index * 2 - 1, (select(index, ...)))
	end

	return packet
end

--[[
    A harness on one side of a mock with one event, whose reader takes a
    byte and a slot per message and delivers them, refusing a zero, with
    every failure recorded and a list for what listeners see
--]]

local function setup(side: string, mode: string, depth: number?, idBytes: number?, spawn: Spawn?): Harness
	local mock: Mock = spawn and Volt.mock(spawn) or Volt.mock(task.spawn)
	local player: any, client: Transport = mock:join("Alice")
	local failures: { Report } = {}
	local runtime: Runtime

	local function read(from: any, packet: buffer, cursor: number, slots: { any }, sideCursor: number, _: number)
		local value: number = buffer.readu8(packet, cursor)
		if value == 0 then
			error("Ping.value: out of range")
		end
		return runtime:deliver(PING, from, cursor + 1, sideCursor + 1, value, slots[sideCursor])
	end

	runtime = Volt.start({
		version = "0.1.0",
		hash = 0,
		scope = "Test",
		side = side,
		idBytes = idBytes or 1,
		options = { flush = 1, manualReplication = false, unreliableBudget = 900 },
		messages = { [PING] = { name = "Ping", kind = "event", mode = mode, queue = depth or 4, read = read } },
		outgoing = {},
	}, side == "server" and mock.server or client)

	runtime:onFailure(function (_, kind: string, detail: string)
		table.insert(failures, { kind = kind, detail = detail })
	end)

	return {
		runtime = runtime,
		mock = mock,
		isServer = side == "server",
		player = player,
		client = client,
		seen = {},
		failures = failures,
	}
end

-- Sends a packet to the harness's runtime from the far end and delivers it
local function send(harness: Harness, packet: buffer, slots: { any }?)
	if harness.isServer then
		harness.client.reliable(nil, packet, slots)
	else
		harness.mock.server.reliable(harness.player, packet, slots)
	end

	harness.mock:step()
end

-- A listener that records what it was called with, one line per call, a player by name
local function watcher(seen: { string }): (...any) -> ()
	return function (...: any)
		local parts: { string } = {}
		for index = 1, select("#", ...) do
			local value: any = (select(index, ...))
			table.insert(parts, typeof(value) == "table" and value.Name or tostring(value))
		end
		table.insert(seen, table.concat(parts, " "))
	end
end

describe("Receive", function ()
	test("delivers every message of a packet in order, the player first on the server", function ()
		local server: Harness = setup("server", "ManySync")

		server.runtime:on(PING, watcher(server.seen))
		send(server, pings(3, 5, 7))

		expect(table.concat(server.seen, ",")).is("Alice 3 nil,Alice 5 nil,Alice 7 nil")
		expect(#server.failures).is(0)
	end)

	test("delivers the values alone on the client", function ()
		local client: Harness = setup("client", "ManySync")

		client.runtime:on(PING, watcher(client.seen))
		send(client, pings(3, 5))

		expect(table.concat(client.seen, ",")).is("3 nil,5 nil")
	end)

	test("hands a reader the packet's side array, and an empty one when it carried none", function ()
		local server: Harness = setup("server", "ManySync")

		server.runtime:on(PING, watcher(server.seen))
		send(server, pings(3, 5), { "first", "second" })
		send(server, pings(7))

		expect(table.concat(server.seen, ",")).is("Alice 3 first,Alice 5 second,Alice 7 nil")
	end)

	test("drops the rest of a packet after an unknown id and reports it once", function ()
		local server: Harness = setup("server", "ManySync")
		local packet: buffer = pings(3, 5, 7)

		buffer.writeu8(packet, 2, 9)
		server.runtime:on(PING, watcher(server.seen))
		send(server, packet)

		expect(table.concat(server.seen, ",")).is("Alice 3 nil")
		expect(#server.failures).is(1)
		expect(server.failures[1].kind).is("decode")
		expect(server.failures[1].detail).is("unknown message 9")
	end)

	test("reports a reader that refuses its bytes as a decode failure without its position", function ()
		local server: Harness = setup("server", "ManySync")

		server.runtime:on(PING, watcher(server.seen))
		send(server, pings(3, 0, 7))

		expect(table.concat(server.seen, ",")).is("Alice 3 nil")
		expect(server.failures[1].kind).is("decode")
		expect(server.failures[1].detail).is("Ping.value: out of range")
	end)

	test("reads two-byte ids and reports one cut short", function ()
		local server: Harness = setup("server", "ManySync", nil, 2)
		local packet: buffer = buffer.create(4)

		buffer.writeu16(packet, 0, PING)
		buffer.writeu8(packet, 2, 3)
		buffer.writeu8(packet, 3, PING)

		server.runtime:on(PING, watcher(server.seen))
		send(server, packet)

		expect(table.concat(server.seen, ",")).is("Alice 3 nil")
		expect(server.failures[1].detail).is("truncated message id")
	end)

	test("reports something that is not a packet and reads nothing", function ()
		local server: Harness = setup("server", "ManySync")

		server.runtime:on(PING, watcher(server.seen))
		server.runtime:packet(server.player, "text", nil)
		server.runtime:packet(server.player, buffer.create(0), 5)

		expect(#server.seen).is(0)
		expect(`{server.failures[1].kind},{server.failures[2].kind}`).is("packet,packet")
	end)

	test("reports a sync listener's error with the event's name and goes on with the packet", function ()
		local server: Harness = setup("server", "ManySync")

		server.runtime:on(PING, function (_, value: number)
			if value == 5 then
				error("boom")
			end
		end)

		server.runtime:on(PING, watcher(server.seen))
		send(server, pings(3, 5, 7))

		expect(table.concat(server.seen, ",")).is("Alice 3 nil,Alice 5 nil,Alice 7 nil")
		expect(#server.failures).is(1)
		expect(server.failures[1].kind).is("listener")
		expect((server.failures[1].detail:find("Ping: ", 1, true))).is(1)
		expect(server.failures[1].detail:find("boom", 1, true) ~= nil).is(true)
	end)

	test("reports a sync listener that yields across a frame and still finishes the packet", function ()
		local server: Harness = setup("server", "ManySync")

		server.runtime:on(PING, function (_, value: number)
			if value == 5 then
				coroutine.yield()
			end
		end)

		server.runtime:on(PING, watcher(server.seen))

		-- The packet is handled on a thread of its own, so the listener's yield can be resumed after a frame
		local thread: thread = coroutine.create(function ()
			server.runtime:packet(server.player, pings(3, 5, 7), nil)
		end)

		coroutine.resume(thread)
		expect(table.concat(server.seen, ",")).is("Alice 3 nil")

		server.mock:step()
		coroutine.resume(thread)

		expect(coroutine.status(thread)).is("dead")
		expect(table.concat(server.seen, ",")).is("Alice 3 nil,Alice 5 nil,Alice 7 nil")
		expect(server.failures[1].kind).is("listener")
		expect(server.failures[1].detail).is("Ping: a sync listener yielded")
	end)

	test("runs an async listener on the transport's scheduler, one thread per message", function ()
		local spawned: number = 0
		local server: Harness = setup("server", "ManyAsync", nil, nil, function (callback: (...any) -> (), ...: any)
			spawned += 1
			callback(...)
		end)

		server.runtime:on(PING, watcher(server.seen))
		send(server, pings(3, 5))

		expect(spawned).is(2)
		expect(table.concat(server.seen, ",")).is("Alice 3 nil,Alice 5 nil")
	end)

	test("calls many listeners in connection order and drops one that disconnected", function ()
		local server: Harness = setup("server", "ManySync")
		local disconnect: () -> () = server.runtime:on(PING, function ()
			table.insert(server.seen, "a")
		end)

		server.runtime:on(PING, function ()
			table.insert(server.seen, "b")
		end)
		
		send(server, pings(3))
		disconnect()
		send(server, pings(5))

		expect(table.concat(server.seen, ",")).is("a,b,b")
	end)

	test("refuses a second listener on a single event instead of replacing the first", function ()
		local server: Harness = setup("server", "SingleSync")

		server.runtime:on(PING, watcher(server.seen))

		local ok: boolean, message: any = pcall(server.runtime.on, server.runtime, PING, watcher(server.seen))
		expect(ok).is(false)
		expect(tostring(message):find("Ping: a listener is already connected", 1, true) ~= nil).is(true)
	end)

	test("queues messages until the first listener and drains them to it in order", function ()
		local server: Harness = setup("server", "SingleAsync")

		send(server, pings(3, 5))
		expect(#server.seen).is(0)

		server.runtime:on(PING, watcher(server.seen))
		expect(table.concat(server.seen, ",")).is("Alice 3 nil,Alice 5 nil")

		send(server, pings(7))
		expect(table.concat(server.seen, ",")).is("Alice 3 nil,Alice 5 nil,Alice 7 nil")
	end)

	test("drops the oldest when the queue is full and reports it once", function ()
		local server: Harness = setup("server", "ManySync", 2)

		send(server, pings(1, 2, 3, 4))
		server.runtime:on(PING, watcher(server.seen))

		expect(table.concat(server.seen, ",")).is("Alice 3 nil,Alice 4 nil")
		expect(#server.failures).is(1)
		expect(server.failures[1].kind).is("queue")
	end)

	test("drains a polled event through iter with the index and the player, then has nothing more", function ()
		local server: Harness = setup("server", "Polling")
		local rows: { string } = {}

		send(server, pings(3, 5))

		for index: number, who: any, value: number, slot: any in server.runtime:iter(PING) do
			table.insert(rows, `{index} {who.Name} {value} {slot}`)
		end

		expect(table.concat(rows, ",")).is("1 Alice 3 nil,2 Alice 5 nil")
		expect((server.runtime:iter(PING)())).is(nil)
	end)

	test("drains a polled event on the client without a player", function ()
		local client: Harness = setup("client", "Polling")
		local rows: { string } = {}

		send(client, pings(3))

		for index: number, value: number, slot: any in client.runtime:iter(PING) do
			table.insert(rows, `{index} {value} {slot}`)
		end

		expect(table.concat(rows, ",")).is("1 3 nil")
	end)
end)
