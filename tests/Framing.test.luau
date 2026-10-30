--[[
    Proves what opens a packet: a channel's byte, then a stamped server's
    time, each counted, with an unreliable run split shorter to leave room
    for them; the default stream flushed first with the handshake, then
    each channel's, then the unreliable; and a channel held with the rest
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local hex = require("./Hex")
local packet = require("./Packet")
local Volt = require("@volt")
local Limits = require("@volt/Limits")
local Send = require("@volt/Send")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock
type Runtime = Volt.Runtime
type Schema = Volt.Schema
type Send = Send.Send
type Stats = Volt.Stats
type Transport = Volt.Transport

type Fired = { target: any, packet: buffer } -- One packet a send fired

local MAX_OUTGOING: number = 256
local BULK: number = 1 -- The one channel's number, and the byte its packets open with
local STAMP: number = 1761700000.25 -- The server time of the design's worked example
local HASH: number = 0x9E3779B9

-- The options the runtime reads, at the compiler's defaults
local OPTIONS: { [string]: any } = {
	flush = 1,
	manualReplication = false,
	maxPacket = 8192,
	maxPacketsPerSecond = 240,
	maxOutgoing = 262144,
	unreliableBudget = 900,
}

-- A send that keeps what it fires, counting into a total, with the budget, channel and stamp given
local function recorded(budget: number?, channel: number?, stamped: boolean?): (Send, { Fired }, Stats)
	local fired: { Fired } = {}
	local total: Stats = Limits.fresh()

	local function fire(target: any, out: buffer)
		table.insert(fired, { target = target, packet = out })
	end

	return Send.new(fire, total, function () end, MAX_OUTGOING, budget, channel, stamped), fired, total
end

-- Writes one message of a count of bytes all holding a value, and marks it
local function message(send: Send, count: number, value: number)
	local offset: number, out: buffer = send.begin(count)

	buffer.fill(out, offset, value, count)
	send.mark()
end

-- Writes one message of the bytes given into a send's current state
local function write(send: Send, bytes: { number })
	local offset: number, out: buffer = send.begin(#bytes)

	buffer.copy(out, offset, packet(bytes))
end

-- The hex of every packet fired, in firing order, one per line
local function lines(fired: { Fired }): string
	local list: { string } = {}

	for _, entry: Fired in fired do
		table.insert(list, hex(entry.packet))
	end

	return table.concat(list, "\n")
end

-- A schema table for one side, with the channel and stamp given, and the outgoing rows given
local function schema(side: string, streams: { string }?, stamp: boolean?, outgoing: { [number]: any }?): Schema
	return {
		version = Volt.version,
		hash = HASH,
		scope = "Test",
		side = side,
		idBytes = 1,
		stamp = stamp,
		streams = streams,
		options = OPTIONS,
		messages = {},
		outgoing = outgoing or {},
	}
end

-- What a raw client side is sent, each packet as hex in arrival order
local function heard(side: Transport): { string }
	local list: { string } = {}

	side.receive(function (_, bytes: buffer)
		table.insert(list, hex(bytes))
	end)

	return list
end

describe("Framing", function ()
	test("a channel's packet opens with its byte, counted in the bytes out", function ()
		local send: Send, fired: { Fired }, total: Stats = recorded(nil, BULK)
		local mine: Stats = Limits.fresh()

		send.current = send:add("a", mine)
		message(send, 3, 9)
		send:flush()

		expect(lines(fired)).is("01 09 09 09")
		expect(`{mine.bytesOut} {total.bytesOut}`).is("4 4")
	end)

	test("an unreliable run is split one byte shorter, leaving room for the channel byte", function ()
		local send: Send, fired: { Fired } = recorded(10, 0)

		send.current = send:add("a", Limits.fresh())
		message(send, 4, 1)
		message(send, 4, 2)
		message(send, 4, 3)
		send:flush()

		expect(lines(fired)).is("00 01 01 01 01 02 02 02 02\n00 03 03 03 03")
	end)

	test("a stamped packet has the channel byte, the flush's time, then its messages, split shorter by both", function ()
		local send: Send, fired: { Fired }, total: Stats = recorded(20, 0, true)

		send.current = send:add("a", Limits.fresh())
		message(send, 6, 1)
		message(send, 6, 2)
		send:flush(STAMP)

		expect(#fired).is(2)
		expect(`{buffer.len(fired[1].packet)} {buffer.len(fired[2].packet)} {total.bytesOut}`).is("15 15 30")
		expect(buffer.readu8(fired[2].packet, 0)).is(0)
		expect(buffer.readf64(fired[2].packet, 1)).is(STAMP)
		expect(buffer.readu8(fired[2].packet, 9)).is(2)
	end)

	test(
		"a client flushes the default stream with its handshake first, then each channel, then the unreliable",
		function ()
			local mock: Mock = Volt.mock(task.spawn)
			local _, transport: Transport = mock:join("Alice")
			local received: { string } = {}

			mock.server.receive(function (_, bytes: buffer)
				table.insert(received, hex(bytes))
			end)

			local client: Runtime = Volt.start(
				schema("client", { "Bulk" }, nil, {
					[1] = { name = "Ping", kind = "event", reliable = true, minBytes = 2, maxBytes = 2 },
					[2] = {
						name = "Chat",
						kind = "event",
						reliable = true,
						stream = BULK,
						minBytes = 2,
						maxBytes = 202,
					},
					[3] = { name = "Tick", kind = "event", reliable = false, minBytes = 2, maxBytes = 2 },
				}),
				transport
			)

			-- Fired out of stream order, which the flush puts back
			write(client.streams[BULK], { 2, 2, 0x68, 0x69 })
			write(client.unreliable, { 3, 7 })
			client.unreliable.mark()
			write(client.reliable, { 1, 3 })

			mock:step()
			mock:step()

			expect(table.concat(received, "\n")).is("00 00 B9 79 37 9E 01 03\n01 02 02 68 69\n00 03 07")
		end
	)

	test(
		"a client's channel frame counts its byte against maxPacket, dropping the message that would pass it",
		function ()
			local mock: Mock = Volt.mock(task.spawn)
			local _, transport: Transport = mock:join("Alice")
			local received: { string } = {}
			local failures: { string } = {}
			local definition: Schema = schema("client", { "Bulk" })
			local options: { [string]: any } = table.clone(OPTIONS)

			options.maxPacket = 8 -- Two four-byte messages fit the cap alone, but not with the byte before them
			definition.options = options

			mock.server.receive(function (_, bytes: buffer)
				table.insert(received, hex(bytes))
			end)

			local client: Runtime = Volt.start(definition, transport)

			client:onFailure(function (_, kind: string, detail: string)
				table.insert(failures, `{kind}: {detail}`)
			end)

			write(client.streams[BULK], { 2, 1, 1, 1 })
			write(client.streams[BULK], { 2, 2, 2, 2 })
			mock:step()
			mock:step()

			expect(table.concat(received, "\n")).is("00 00 B9 79 37 9E\n01 02 01 01 01")
			expect(table.concat(failures, ",")).is("outgoing: over maxPacket, a message was dropped")
		end
	)

	test("a stamped server's packet opens with the time the mock's clock read when the flush began", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local alice: any, side: Transport = mock:join("Alice")
		local server: Runtime = Volt.start(schema("server", nil, true), mock.server)
		local received: { string } = heard(side)

		side.reliable(nil, packet({ 0, 0xB9, 0x79, 0x37, 0x9E }))
		mock:step()

		server:target(alice)
		write(server.reliable, { 1, 7, 0, 30 })
		mock.time = STAMP

		mock:step()
		mock:step()

		expect(table.concat(received, "\n")).is("00 00 10 28 5A 40 DA 41 01 07 00 1E")
	end)

	test(
		"a joiner's channel state is held with the default one, and both go out after the handshake in order",
		function ()
			local mock: Mock = Volt.mock(task.spawn)
			local alice: any, side: Transport = mock:join("Alice")
			local server: Runtime = Volt.start(schema("server", { "Bulk" }), mock.server)
			local received: { string } = heard(side)

			expect(server:target(alice, BULK)).is(true)
			write(server.streams[BULK], { 2, 6 })
			write(server.reliable, { 1, 5 })

			mock:step()
			mock:step()

			expect(#received).is(0)

			side.reliable(nil, packet({ 0, 0, 0xB9, 0x79, 0x37, 0x9E }))
			mock:step()
			mock:step()

			expect(table.concat(received, "\n")).is("00 01 05\n01 02 06")
			expect(server:stats(alice).bytesOut).is(6)
		end
	)

	test("an unchecked fire and a broadcast of a channel's event take the channel's send", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local alice: any, side: Transport = mock:join("Alice")
		local server: Runtime = Volt.start(
			schema("server", { "Bulk" }, nil, {
				[2] = { name = "Chat", kind = "event", reliable = true, stream = BULK, minBytes = 2, maxBytes = 2 },
			}),
			mock.server
		)
		local received: { string } = heard(side)

		local function writeChat(value: any)
			local offset: number, out: buffer = server.streams[BULK].begin(2)

			buffer.writeu8(out, offset, 2)
			buffer.writeu8(out, offset + 1, value)
		end

		-- A value of the wrong kind raises part way, after the id, which the channel's send takes back
		server:target(alice, BULK)

		local ok: boolean, raised: any = pcall(server.write, server, 2, writeChat, "six")

		server:broadcast(2, nil, nil, writeChat, 6)
		side.reliable(nil, packet({ 0, 0, 0xB9, 0x79, 0x37, 0x9E }))
		mock:step()
		mock:step()

		expect(ok).is(false)
		expect(tostring(raised):sub(1, 6)).is("Chat: ")
		expect(table.concat(received, "\n")).is("01 02 06")
	end)
end)
