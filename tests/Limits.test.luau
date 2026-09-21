--[[
    Proves the limits: what the server drops before decoding, which is a
    packet before the handshake, one with the wrong hash, which kicks,
    one over maxPacket and one past the packet rate; the message past its
    event's or function's rate; the outgoing cap; the counters; and over
    the generated modules the handshake passing and failing
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local handshake = require("./Handshake")
local Volt = require("@volt")
local Config = require("@volt/Config/Runtime")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock
type Runtime = Volt.Runtime
type Stats = Volt.Stats
type Transport = Volt.Transport

type Report = { kind: string, detail: string } -- One failure the server reported

-- A server runtime over a mock with two events, one rate limited, and what it heard and reported
type Harness = {
	runtime: Runtime,
	mock: Mock,
	player: any,
	client: Transport, -- The joined player's raw client side
	seen: { string },
	failures: { Report },
}

local HASH: number = 0x1234ABCD -- The server's schema hash
local PING: number = 1 -- The rate-limited event's id
local PONG: number = 2 -- The unlimited event's id
local RATE: number = 2 -- Pings a player may send a second
local MAX_PACKET: number = 16
local MAX_PACKETS: number = 3 -- Packets a player may send a second
local INPUT_RATE: number = 120 -- What Events.volt leaves Input at, the file's default
local ECHO_RATE: number = 60 -- What Functions.volt leaves Echo at, the file's default

-- A packet from a flat list of id and value bytes
local function packet(bytes: { number }): buffer
	local out: buffer = buffer.create(#bytes)
	for index: number, byte: number in bytes do
		buffer.writeu8(out, index - 1, byte)
	end
	return out
end

-- A packet of two others, one after the other
local function joined(first: buffer, second: buffer): buffer
	local out: buffer = buffer.create(buffer.len(first) + buffer.len(second))
	buffer.copy(out, 0, first)
	buffer.copy(out, buffer.len(first), second)
	return out
end

local function setup(): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local player: any, client: Transport = mock:join("Alice")
	local seen: { string } = {}
	local runtime: Runtime

	-- A reader per event, each a byte of value, delivering it
	local function reader(id: number)
		return function (from: any, bytes: buffer, cursor: number, _: { any }, sideCursor: number, _: number)
			return runtime:deliver(id, from, cursor + 1, sideCursor, buffer.readu8(bytes, cursor))
		end
	end

	runtime = Volt.start({
		version = Volt.version,
		hash = HASH,
		scope = "Test",
		side = "server",
		idBytes = 1,
		options = {
			flush = 1,
			manualReplication = false,
			maxPacket = MAX_PACKET,
			maxPacketsPerSecond = MAX_PACKETS,
			unreliableBudget = 900,
		},
		messages = {
			[PING] = { name = "Ping", kind = "event", mode = "ManySync", queue = 4, rate = RATE, read = reader(PING) },
			[PONG] = { name = "Pong", kind = "event", mode = "ManySync", queue = 4, read = reader(PONG) },
		},
		outgoing = {},
	}, mock.server)

	runtime:on(PING, function (_, value: number)
		table.insert(seen, `ping {value}`)
	end)
	runtime:on(PONG, function (_, value: number)
		table.insert(seen, `pong {value}`)
	end)

	return { runtime = runtime, mock = mock, player = player, client = client, seen = seen, failures = {} }
end

-- Records every failure from here on, in place of the handler the runtime starts with
local function recording(harness: Harness)
	harness.runtime:onFailure(function (_, kind: string, detail: string)
		table.insert(harness.failures, { kind = kind, detail = detail })
	end)
end

-- Sends a packet from the player and delivers it
local function send(harness: Harness, bytes: buffer)
	harness.client.reliable(nil, bytes)
	harness.mock:step()
end

describe("Limits", function ()
	test("reads nothing from a player before their handshake and drops the packet", function ()
		local harness: Harness = setup()

		recording(harness)
		send(harness, packet({ PING, 3 }))

		expect(#harness.seen).is(0)
		expect(`{harness.failures[1].kind}: {harness.failures[1].detail}`).is("packet: before the handshake")
	end)

	test("kicks a player whose hash differs, naming both hashes, unless the game handles it", function ()
		local harness: Harness = setup()

		send(harness, handshake(0x9E3779B9))

		expect(harness.player.kicked).is("Volt: schema mismatch (client 0x9E3779B9, server 0x1234ABCD)")
		expect(#harness.mock.players).is(0)
		expect(harness.runtime:stats().failures.handshake).is(1)
	end)

	test("admits the handshake, reads what follows it in the same packet, and expects no second", function ()
		local harness: Harness = setup()

		recording(harness)
		send(harness, joined(handshake(HASH), packet({ PING, 3 })))
		send(harness, handshake(HASH))

		expect(table.concat(harness.seen, ",")).is("ping 3")
		expect(#harness.failures).is(1)
		expect(harness.failures[1].detail).is("unknown message 0")
	end)

	test("drops a packet over maxPacket unread", function ()
		local harness: Harness = setup()

		recording(harness)
		send(harness, handshake(HASH))
		send(harness, buffer.create(MAX_PACKET + 1))

		expect(#harness.seen).is(0)
		expect(harness.failures[1].kind).is("packet")
		expect(harness.failures[1].detail).is(`{MAX_PACKET + 1} bytes, over maxPacket`)
	end)

	test("drops the packets past a player's rate for the second", function ()
		local harness: Harness = setup()

		recording(harness)
		send(harness, handshake(HASH))
		send(harness, packet({ PONG, 1 }))
		send(harness, packet({ PONG, 2 }))
		send(harness, packet({ PONG, 3 }))

		expect(table.concat(harness.seen, ",")).is("pong 1,pong 2")
		expect(harness.failures[1].kind).is("rate")
		expect(harness.failures[1].detail).is(`over {MAX_PACKETS} packets a second`)
	end)

	test("decodes a message past its event's rate, drops it, and reads on", function ()
		local harness: Harness = setup()

		recording(harness)
		send(harness, handshake(HASH))
		send(harness, packet({ PING, 1, PING, 2, PING, 3, PONG, 4 }))

		expect(table.concat(harness.seen, ",")).is("ping 1,ping 2,pong 4")
		expect(#harness.failures).is(1)
		expect(harness.failures[1].detail).is(`Ping: over {RATE} a second`)
	end)

	test("counts packets, bytes and messages in and failures by kind, for the player and in total", function ()
		local harness: Harness = setup()
		local player: any = harness.player
		local bytes: number = 5 + 6 + MAX_PACKET + 1 -- The handshake, three messages, and the oversized packet

		recording(harness)
		send(harness, handshake(HASH))
		send(harness, packet({ PING, 1, PING, 2, PING, 3 }))
		send(harness, buffer.create(MAX_PACKET + 1))

		local mine: Stats = harness.runtime:stats(player)
		local total: Stats = harness.runtime:stats()

		expect(`{mine.packetsIn} {mine.bytesIn} {mine.messagesIn}`).is(`3 {bytes} 3`)
		expect(`{mine.failures.rate} {mine.failures.packet}`).is("1 1")
		expect(`{total.packetsIn} {total.bytesIn} {total.messagesIn}`).is(`3 {bytes} 3`)

		harness.mock:leave(player)

		expect(harness.runtime:stats(player).packetsIn).is(0)
		expect(harness.runtime:stats().packetsIn).is(3)
	end)

	test("drops the message that takes a player's frame past the cap and counts it as outgoing", function ()
		local harness: Harness = setup()
		local runtime: Runtime = harness.runtime

		recording(harness)
		runtime:target(harness.player)
		runtime.reliable.begin(Config.maxOutgoing + 1)
		runtime.reliable.begin(1)

		expect(harness.failures[1].kind).is("outgoing")
		expect(runtime:stats(harness.player).failures.outgoing).is(1)
		expect(runtime.reliable.current.cursor).is(1)
	end)

	describe("over the generated modules", function ()
		local EVENTS: string = fs.readFile("tests/Schemas/Events.volt")
		local CLIENT: string, SERVER: string = Generated.modules("Events", EVENTS)

		-- Counts a runtime's failures without the warnings the handler it starts with would print
		local function quiet(server: any)
			server.onFailure(function () end)
		end

		-- A server and one client over a mock, the generated module of each side, the client's from the text given
		local function modules(client: string): (Mock, any, any, any)
			local mock: Mock = Volt.mock(task.spawn)
			local alice, transport = mock:join("Alice")
			local server: any = Generated.module("Server", SERVER, mock.server)

			return mock, alice, server, Generated.module("Client", client, transport)
		end

		-- One step flushes what was fired and the next delivers it
		local function exchange(mock: Mock)
			mock:step()
			mock:step()
		end

		test("the handshake passes and the client is heard", function ()
			local mock: Mock, alice, server, client = modules(CLIENT)
			local heard: number = 0

			server.Ready.on(function ()
				heard += 1
			end)

			client.Ready.fire()
			exchange(mock)

			expect(heard).is(1)
			expect((next(server.stats(alice).failures))).is(nil)
		end)

		test("a client built from an edited schema is kicked with both hashes in the message", function ()
			local edited: string = Generated.modules("Events", (EVENTS:gsub("u8%(0%.%.8%)", "u8(0..9)")))
			local clientHash: string = edited:match("hash = (0x%x+)") :: string
			local serverHash: string = SERVER:match("hash = (0x%x+)") :: string
			local mock: Mock, alice, server, client = modules(edited)

			client.Ready.fire()
			exchange(mock)

			expect(clientHash ~= serverHash).is(true)
			expect(alice.kicked).is(`Volt: schema mismatch (client {clientHash}, server {serverHash})`)
			expect(server.stats().failures.handshake).is(1)
		end)

		test("the message past an event's rate is dropped and the rest of the frame heard", function ()
			local mock: Mock, alice, server, client = modules(CLIENT)
			local inputs: number, ready: number = 0, 0

			quiet(server)
			server.Input.on(function ()
				inputs += 1
			end)
			server.Ready.on(function ()
				ready += 1
			end)

			for _ = 1, INPUT_RATE + 1 do
				client.Input.fire(1, false)
			end

			client.Ready.fire()
			exchange(mock)

			expect(`{inputs} {ready}`).is(`{INPUT_RATE} 1`)
			expect(server.stats(alice).failures.rate).is(1)
		end)

		test("the call past a function's rate is refused with rate limited", function ()
			local clientText: string, serverText: string =
				Generated.modules("Functions", fs.readFile("tests/Schemas/Functions.volt"))
			local mock: Mock = Volt.mock(task.spawn)
			local _, transport = mock:join("Alice")
			local server: any = Generated.module("Server", serverText, mock.server)
			local client: any = Generated.module("Client", clientText, transport)
			local results: { string } = {}

			quiet(server)
			server.Echo.on(function (_, value: number): number
				return value
			end)

			for index: number = 1, ECHO_RATE + 1 do
				task.spawn(function ()
					local ok: boolean, value: any = client.Echo.invoke(index)
					results[index] = `{ok} {value}`
				end)
			end

			mock:step()
			mock:step()
			mock:step()

			expect(results[ECHO_RATE]).is(`true {ECHO_RATE}`)
			expect(results[ECHO_RATE + 1]).is("false rate limited")
			expect(server.stats().failures.rate).is(1)
		end)
	end)
end)
