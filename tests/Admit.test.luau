--[[
    Proves what admit reads before the loop in a schema with a channel or
    a stamp: the channel byte on either side, a byte past the last channel
    or none at all refused, every stream within one packet rate, the one
    handshake after byte 0, and the stamp a client hands to serverTime
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local packet = require("./Packet")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock
type Runtime = Volt.Runtime
type Transport = Volt.Transport

type Report = { player: any, kind: string, detail: string } -- One failure a runtime reported

-- A runtime on one side of a mock with one event, and what it heard and reported
type Harness = {
	runtime: Runtime,
	mock: Mock,
	isServer: boolean,
	player: any,
	client: Transport, -- The joined player's client side, the far end of a server harness
	seen: { string },
	failures: { Report },
}

local PING: number = 1 -- The one event's id
local MAX_PACKETS: number = 3 -- Packets a player may send a second
local HASH: number = 0x1234ABCD
local HANDSHAKE: { number } = { 0, 0xCD, 0xAB, 0x34, 0x12 } -- The handshake for HASH, after any channel byte
local BULK: { string } = { "Bulk" } -- One channel, numbered 1

-- The options the runtime reads, at the compiler's defaults but for the packet rate
local OPTIONS: { [string]: any } = {
	flush = 1,
	manualReplication = false,
	maxPacket = 8192,
	maxPacketsPerSecond = MAX_PACKETS,
	maxOutgoing = 262144,
	unreliableBudget = 900,
}

-- The bytes of each list given, one after another, as one packet
local function packed(...: { number }): buffer
	local list: { number } = {}

	for index: number = 1, select("#", ...) do
		local part: { number } = (select(index, ...))
		table.move(part, 1, #part, #list + 1, list)
	end

	return packet(list)
end

-- A server packet opening with the time it was flushed at, then the bytes given
local function stamped(time: number, after: { number }): buffer
	local out: buffer = buffer.create(8 + #after)

	buffer.writef64(out, 0, time)
	buffer.copy(out, 8, packet(after))

	return out
end

--[[
    A harness on one side of a mock with one event, Ping, whose reader
    delivers one byte of value, in a schema with the channels and stamp
    given, every failure recorded and every Ping heard listed unless the
    event is polled
--]]

local function setup(side: string, streams: { string }?, stamp: boolean?, mode: string?): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local player: any, client: Transport = mock:join("Alice")
	local seen: { string } = {}
	local failures: { Report } = {}
	local runtime: Runtime

	local function read(from: any, data: buffer, cursor: number, _: { any }, sideCursor: number, _: number)
		return runtime:deliver(PING, from, cursor + 1, sideCursor, buffer.readu8(data, cursor))
	end

	runtime = Volt.start({
		version = Volt.version,
		hash = HASH,
		scope = "Test",
		side = side,
		idBytes = 1,
		stamp = stamp,
		streams = streams,
		options = OPTIONS,
		messages = { [PING] = { name = "Ping", kind = "event", mode = mode or "ManySync", queue = 4, read = read } },
		outgoing = {},
	}, side == "server" and mock.server or client)

	runtime:onFailure(function (who: any, kind: string, detail: string)
		table.insert(failures, { player = who, kind = kind, detail = detail })
	end)

	if mode ~= "Polling" then
		runtime:on(PING, function (...: any)
			table.insert(seen, `ping {(select(select("#", ...), ...))}`)
		end)
	end

	return {
		runtime = runtime,
		mock = mock,
		isServer = side == "server",
		player = player,
		client = client,
		seen = seen,
		failures = failures,
	}
end

-- Sends a packet to the harness's runtime from the far end and delivers it
local function send(harness: Harness, out: buffer)
	if harness.isServer then
		harness.client.reliable(nil, out)
	else
		harness.mock.server.reliable(harness.player, out)
	end

	harness.mock:step()
end

-- Each failure reported, as its kind and detail, one after another
local function reported(harness: Harness): string
	local list: { string } = {}

	for _, report: Report in harness.failures do
		table.insert(list, `{report.kind}: {report.detail}`)
	end

	return table.concat(list, ",")
end

describe("Admit", function ()
	describe("the channel byte", function ()
		test("the handshake after byte 0 is accepted, and a Ping after byte 1 is then heard once", function ()
			local harness: Harness = setup("server", BULK)

			send(harness, packed({ 0 }, HANDSHAKE))
			send(harness, packed({ 1, PING, 3 }))

			expect(table.concat(harness.seen, ",")).is("ping 3")
			expect(#harness.failures).is(0)
		end)

		test("a byte past the last channel names it, and a packet with no byte is refused", function ()
			local harness: Harness = setup("server", BULK)

			send(harness, packed({ 0 }, HANDSHAKE))
			send(harness, packed({ 2, PING, 3 }))
			send(harness, buffer.create(0))

			expect(#harness.seen).is(0)
			expect(reported(harness)).is("packet: unknown channel 2,packet: no channel byte")
		end)

		test("a packet on a channel before the handshake is dropped as before the handshake", function ()
			local harness: Harness = setup("server", BULK)

			send(harness, packed({ 1, PING, 3 }))

			expect(#harness.seen).is(0)
			expect(reported(harness)).is("packet: before the handshake")
		end)

		test("every stream's packets spend the one packet rate", function ()
			local harness: Harness = setup("server", BULK)

			send(harness, packed({ 0 }, HANDSHAKE))
			send(harness, packed({ 1, PING, 3 }))
			send(harness, packed({ 0, PING, 4 }))
			send(harness, packed({ 1, PING, 5 }))

			expect(table.concat(harness.seen, ",")).is("ping 3,ping 4")
			expect(reported(harness)).is(`rate: over {MAX_PACKETS} packets a second`)
		end)

		test("a second handshake after byte 1 is an unknown message", function ()
			local harness: Harness = setup("server", BULK)

			send(harness, packed({ 0 }, HANDSHAKE))
			send(harness, packed({ 1 }, HANDSHAKE))

			expect(reported(harness)).is("packet: unknown message 0")
		end)

		test("the client refuses a server packet naming no channel, with no player", function ()
			local harness: Harness = setup("client", BULK)

			send(harness, packed({ 5, PING, 3 }))
			send(harness, packed({ 1, PING, 4 }))

			expect(table.concat(harness.seen, ",")).is("ping 4")
			expect(reported(harness)).is("packet: unknown channel 5")
			expect(harness.failures[1].player).is(nil)
		end)

		test("a channel message fired in the client's first frame is read once its handshake is accepted", function ()
			local harness: Harness = setup("server", BULK)
			local client: Runtime = Volt.start({
				version = Volt.version,
				hash = HASH,
				scope = "Test",
				side = "client",
				idBytes = 1,
				streams = BULK,
				options = OPTIONS,
				messages = {},
				outgoing = {
					[PING] = { name = "Ping", kind = "event", reliable = true, stream = 1, minBytes = 2, maxBytes = 2 },
				},
			}, harness.client)

			-- Only the channel is written to, so the default stream's packet holds the handshake alone
			local offset: number, out: buffer = client.streams[1].begin(2)

			buffer.writeu8(out, offset, PING)
			buffer.writeu8(out, offset + 1, 9)

			harness.mock:step()
			harness.mock:step()

			expect(table.concat(harness.seen, ",")).is("ping 9")
			expect(#harness.failures).is(0)
		end)
	end)

	describe("the stamp", function ()
		test("a listener reads the stamp of the packet holding its message, after 0 before any packet", function ()
			local harness: Harness = setup("client", nil, true)
			local times: { number } = { harness.runtime:serverTime() }

			harness.runtime:on(PING, function ()
				table.insert(times, harness.runtime:serverTime())
			end)

			send(harness, stamped(10.5, { PING, 3 }))

			expect(table.concat(times, ",")).is("0,10.5")
			expect(table.concat(harness.seen, ",")).is("ping 3")
		end)

		test("a queued message keeps its packet's stamp inside iter, and the newest is read after", function ()
			local harness: Harness = setup("client", nil, true, "Polling")
			local times: { number } = {}

			send(harness, stamped(10, { PING, 1 }))
			send(harness, stamped(20, { PING, 2 }))

			for _ in harness.runtime:iter(PING) do
				table.insert(times, harness.runtime:serverTime())
			end

			table.insert(times, harness.runtime:serverTime())

			expect(table.concat(times, ",")).is("10,20,20")
		end)

		test("comes after the channel byte, and a packet shorter than it is refused", function ()
			local harness: Harness = setup("client", BULK, true)
			local whole: buffer = buffer.create(11)

			buffer.writef64(whole, 1, 30)
			buffer.writeu8(whole, 9, PING)
			buffer.writeu8(whole, 10, 4)

			send(harness, packet({ 0, 1, 2, 3, 4, 5, 6, 7 }))
			send(harness, whole)

			expect(reported(harness)).is("packet: shorter than its stamp")
			expect(table.concat(harness.seen, ",")).is("ping 4")
			expect(harness.runtime:serverTime()).is(30)
		end)
	end)
end)
