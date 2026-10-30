--[[
    Proves the string dictionary over the mock, with a writer and a reader
    written by hand as generated ones would be: ids given in order up to
    the capacity, the entries a player lacks sent just ahead of their next
    packet, held or not, and the client taking a message whole or not at all
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local Handshake = require("./Handshake")
local hex = require("./Hex")
local packet = require("./Packet")
local Volt = require("@volt")
local Config = require("@volt/Config/Runtime")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock
type Runtime = Volt.Runtime
type Schema = Volt.Schema
type Stats = Volt.Stats
type Transport = Volt.Transport

type Report = { player: any, kind: string, detail: string } -- One failure the client reported

-- A client runtime with every string its listener heard and what it reported
type Client = { runtime: Runtime, heard: { string }, failures: { Report } }

-- A server over a mock, its writer of one string, and a fire of it at one player
type Harness = {
	mock: Mock,
	server: Runtime,
	write: (value: string) -> (),
	pick: (player: any, value: string) -> (),
}

local PICKED: number = 1 -- A plain event of one dictionary string, its id a u16, toward the client
local HASH: number = 0x9E3779B9
local STAMP: number = 1761700000.25 -- The server time of the design's worked example
local ENTRIES: number = Config.dictionaryEntries
local SWORD: string = "00 01 00 01 00 05 53 77 6F 72 64" -- The dictionary message of one entry, "Sword", as id 1

-- The options the runtime reads, at the compiler's defaults
local OPTIONS: { [string]: any } = {
	flush = 1,
	manualReplication = false,
	maxPacket = 8192,
	maxPacketsPerSecond = 240,
	maxOutgoing = 262144,
	unreliableBudget = 900,
}

-- A schema table on one side with the dictionary's id width given, or none, and the stamp and channels given
local function schema(side: string, width: number?, stamp: boolean?, streams: { string }?): Schema
	local row: { [string]: any } = { name = "picked", kind = "event", reliable = true, minBytes = 3, maxBytes = 3 }

	return {
		version = Volt.version,
		hash = HASH,
		scope = "Test",
		side = side,
		idBytes = 1,
		stamp = stamp,
		streams = streams,
		dictionary = width,
		options = OPTIONS,
		messages = {},
		outgoing = { [PICKED] = row },
	}
end

-- A server whose writer names a string by its dictionary id, refused when the dictionary has no room for it
local function setup(width: number?, stamp: boolean?, streams: { string }?): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local server: Runtime

	local function writePicked(value: string)
		local offset: number, out: buffer = server.reliable.begin(3)
		local id: number = server.intern(value)

		buffer.writeu8(out, offset, PICKED)

		if id == 0 then
			server.reliable.refuse("picked: dictionary full")
		end

		buffer.writeu16(out, offset + 1, id)
	end

	server = Volt.start(schema("server", width, stamp, streams), mock.server)

	return {
		mock = mock,
		server = server,
		write = writePicked,

		pick = function (player: any, value: string)
			if server:target(player) then
				writePicked(value)
			end
		end,
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

-- A player whose raw client side records what it is sent and has sent its handshake, read at the next step
local function joined(harness: Harness, name: string): (any, { string })
	local player: any, side: Transport = harness.mock:join(name)
	local list: { string } = heard(side)

	side.reliable(nil, Handshake(HASH))

	return player, list
end

-- A client runtime whose reader looks each id up in the dictionary the server sent it
local function client(transport: Transport, width: number?): Client
	local heardStrings: { string } = {}
	local failures: { Report } = {}
	local runtime: Runtime

	local function readPicked(_: any, from: buffer, cursor: number, _: { any }, sideCursor: number, _: number)
		local entry: string? = runtime.dictionary[buffer.readu16(from, cursor)]
		if entry == nil then
			error("picked: unknown dictionary id", 0)
		end

		return runtime:deliver(PICKED, nil, cursor + 2, sideCursor, entry)
	end

	local definition: Schema = schema("client", width)

	definition.messages =
		{ [PICKED] = { name = "picked", kind = "event", mode = "ManySync", queue = 64, read = readPicked } }
	definition.outgoing = {}
	runtime = Volt.start(definition, transport)

	runtime:onFailure(function (player: any, kind: string, detail: string)
		table.insert(failures, { player = player, kind = kind, detail = detail })
	end)

	runtime:on(PICKED, function (value: string)
		table.insert(heardStrings, value)
	end)

	return { runtime = runtime, heard = heardStrings, failures = failures }
end

-- Steps until what the server wrote this frame has reached the client sides
local function round(harness: Harness)
	harness.mock:step()
	harness.mock:step()
end

describe("Dictionary", function ()
	test("intern gives a new string the next id and one it holds its own again", function ()
		local server: Runtime = setup(1).server
		local ids: string = `{server.intern("Sword")} {server.intern("Bow")} {server.intern("Sword")}`

		expect(ids).is("1 2 1")
		expect(table.concat(server.dictionary, ",")).is("Sword,Bow")
	end)

	test("intern gives 0 once the dictionary is full, and still finds every string it holds", function ()
		local server: Runtime = setup(1).server

		for index: number = 1, ENTRIES do
			server.intern(`item {index}`)
		end

		local ids: string = `{server.intern("one more")} {server.intern("item 1")} {server.intern(`item {ENTRIES}`)}`

		expect(ids).is(`0 1 {ENTRIES}`)
		expect(#server.dictionary).is(ENTRIES)
	end)

	test("a player is sent the entries they lack just ahead of their next packet, counted as a message", function ()
		local harness: Harness = setup(1)
		local alice: any, received: { string } = joined(harness, "Alice")

		harness.mock:step()

		harness.pick(alice, "Sword")
		round(harness)
		harness.pick(alice, "Sword")
		round(harness)
		harness.pick(alice, "Bow")
		round(harness)

		local mine: Stats = harness.server:stats(alice)
		local sent: number = harness.server:traffic(alice)

		expect(table.concat(received, "\n")).is(`{SWORD}\n01 01 00\n01 01 00\n00 02 00 01 00 03 42 6F 77\n01 02 00`)
		expect(`{mine.messagesOut} {mine.packetsOut} {mine.bytesOut} {sent}`).is("5 5 29 29")
	end)

	test("a joiner is sent the whole dictionary ahead of what was held for them, and decodes it", function ()
		local harness: Harness = setup(1)
		local bob: any = joined(harness, "Bob")

		harness.mock:step()
		harness.pick(bob, "Sword")
		harness.pick(bob, "Bow")
		round(harness)

		-- Carol's raw side records the bytes, and Alice's client starts only after the server has fired at her
		local carol: any, side: Transport = harness.mock:join("Carol")
		local alice: any, transport: Transport = harness.mock:join("Alice")
		local received: { string } = heard(side)

		harness.pick(carol, "Bow")
		harness.pick(alice, "Bow")
		round(harness)

		expect(#received).is(0)

		side.reliable(nil, Handshake(HASH))

		local listener: Client = client(transport, 1)

		round(harness)
		round(harness)

		expect(table.concat(received, "\n")).is("00 01 00 02 00 05 53 77 6F 72 64 03 42 6F 77\n01 02 00")
		expect(table.concat(listener.heard, ",")).is("Bow")
		expect(table.concat(listener.runtime.dictionary, ",")).is("Sword,Bow")
		expect(#listener.failures).is(0)
	end)

	test("players holding as many entries share one message, built once per flush", function ()
		local harness: Harness = setup(1)
		local alice: any, first: { string } = joined(harness, "Alice")
		local bob: any, second: { string } = joined(harness, "Bob")

		harness.mock:step()
		harness.pick(alice, "Sword")
		harness.pick(bob, "Sword")
		round(harness)

		local _, third: { string } = joined(harness, "Carol")
		local owed: { [number]: buffer } = (harness.server :: any)._owed
		local built: number = 0

		harness.mock:step()
		harness.server:broadcast(PICKED, nil, nil, harness.write, "Bow")
		harness.mock:step()

		for _ in owed do
			built += 1
		end

		harness.mock:step()

		expect(built).is(2)
		expect(`{first[3]} {second[3]}`).is("00 02 00 01 00 03 42 6F 77 00 02 00 01 00 03 42 6F 77")
		expect(table.concat(third, "\n")).is("00 01 00 02 00 05 53 77 6F 72 64 03 42 6F 77\n01 02 00")
	end)

	test("with channels and a stamp, the dictionary message opens as the default stream's packets do", function ()
		local harness: Harness = setup(1, true, { "Bulk" })
		local alice: any, side: Transport = harness.mock:join("Alice")
		local received: { string } = heard(side)

		side.reliable(nil, packet({ 0, 0, 0xB9, 0x79, 0x37, 0x9E }))
		harness.mock:step()

		harness.mock.time = STAMP
		harness.pick(alice, "Sword")
		round(harness)

		expect(table.concat(received, "\n")).is(
			`00 00 00 10 28 5A 40 DA 41 {SWORD}\n00 00 00 10 28 5A 40 DA 41 01 01 00`
		)
	end)

	test("the dictionary message's id is as wide as an id toward the client", function ()
		local harness: Harness = setup(2)
		local alice: any, received: { string } = joined(harness, "Alice")

		harness.mock:step()
		harness.pick(alice, "Sword")
		round(harness)

		expect(received[1]).is(`00 {SWORD}`)
	end)

	test("a bot is sent the entries it lacks ahead of its packets as a player is", function ()
		local harness: Harness = setup(1)
		local bot: Volt.Bot = harness.mock:addBot("Helper")
		local side: Transport = harness.mock:connectBot(bot)
		local received: { string } = heard(side)

		side.heartbeat(function () end)
		harness.pick(bot, "Sword")
		round(harness)

		expect(table.concat(received, "\n")).is(`{SWORD}\n01 01 00`)
		expect(harness.server:stats(bot).messagesOut).is(2)
	end)

	test("a client takes a dictionary message whole or not at all, each refusal a decode failure", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local alice: any, transport: Transport = mock:join("Alice")
		local listener: Client = client(transport, 1)

		local refusals: { { bytes: { number }, detail: string } } = {
			{ bytes = { 0, 1, 0 }, detail = "truncated" }, -- The header cut short
			{ bytes = { 0, 2, 0, 1, 0, 1, 0x41 }, detail = "out of order" },
			{ bytes = { 0, 1, 0, 0, 0 }, detail = "no entries" },
			{ bytes = { 0, 1, 0, 0x01, 0x10 }, detail = `past {ENTRIES} entries` }, -- 4,097 of them
			{ bytes = { 0, 1, 0, 1, 0 }, detail = "truncated" }, -- No length byte
			{ bytes = { 0, 1, 0, 2, 0, 1, 0x41, 5, 0x42 }, detail = "truncated" }, -- A whole first entry, then one past the packet
		}

		for _, refusal in refusals do
			mock.server.reliable(alice, packet(refusal.bytes))
		end

		mock:step()

		for index: number, refusal in refusals do
			local report: Report = listener.failures[index]
			expect(`{report.player} {report.kind} {report.detail}`).is(`nil decode Volt.dictionary: {refusal.detail}`)
		end

		expect(`{#listener.failures} {#listener.runtime.dictionary}`).is(`{#refusals} 0`)

		mock.server.reliable(alice, packet({ 0, 1, 0, 1, 0, 1, 0x41, PICKED, 1, 0 }))
		mock:step()

		expect(`{table.concat(listener.runtime.dictionary, ",")} {table.concat(listener.heard, ",")}`).is("A A")
	end)

	test("without a dictionary in its schema, a server sends none and a client reads id 0 as no message", function ()
		local harness: Harness = setup()
		local alice: any, received: { string } = joined(harness, "Alice")
		local bob: any, transport: Transport = harness.mock:join("Bob")
		local listener: Client = client(transport)

		harness.mock:step()
		harness.pick(alice, "Sword")
		round(harness)

		harness.mock.server.reliable(bob, packet({ 0, 1, 0, 1, 0, 1, 0x41 }))
		harness.mock:step()

		local report: Report = listener.failures[1]

		expect(table.concat(received, "\n")).is("01 01 00")
		expect(`{#listener.failures} {report.kind} {report.detail} {#listener.runtime.dictionary}`).is(
			"1 packet unknown message 0 0"
		)
	end)
end)
