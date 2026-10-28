--[[
    Proves the failure detail contract over the generated modules, on the
    server and on the client: every failure of a message begins with its
    registry name and a colon exactly once, a failure of a packet names no
    message, and a handler's error reaches its caller as exactly its text
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local handshake = require("./Handshake")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock
type Transport = Volt.Transport

type Report = { kind: string, detail: string } -- One failure a side reported

-- A server and one client over a mock, each running its side's module, and what each side reported
type Harness = {
	mock: Mock,
	player: any,
	transport: Transport, -- The player's client side, which a raw packet is sent through
	server: any,
	client: any,
	hash: number,
	names: { [string]: boolean }, -- Every registry name either side has
	failures: { server: { Report }, client: { Report } },
}

-- Unchecked, so a value only a reader refuses can be sent; the reply path and the readers are checked in every build
local SCHEMAS: { string } = { "Events", "Functions", "Exports", "Records", "Example" }
local QUEUE: number = 64 -- The queue every event here keeps, the schema's default
local MAX_PACKETS: number = 240 -- The packets a player may send a second, the schema's default
local MAX_PACKET: number = 8192 -- What a client's reliable frame is capped at, the schema's default
local MAX_OUTGOING: number = 262144 -- What a player's frame, and so their hold, is capped at, the schema's default
local SYNC_BYTES: number = 2 -- Sync's id and its u8, as the server fires it
local WRONG_HASH: number = 0xBAD
local UNKNOWN_ID: number = 255 -- An id no schema here gives a message
local LONG_REASON: number = 200 -- Past the 128 bytes Example's Inventory.Transfer allows its reason
local OUT_OF_RANGE: number = 1000 -- Past the 999 a Stack's quantity allows
local WRONG_DIR: number = 9 -- Past the 8 Input's dir allows
local READY: number = 3 -- Ready's id on the server, which a raw packet before the handshake opens with
local PAST_RATE: number = 5 -- Packets past the rate in one step

local MODULES: { [string]: { client: string, server: string } } = {}

for _, name: string in SCHEMAS do
	local source: string = `option writeValidation = false\n{fs.readFile(`tests/Schemas/{name}.volt`)}`
	local client: string, server: string = Generated.modules(name, source)

	MODULES[name] = { client = client, server = server }
end

-- A packet from a flat list of bytes
local function packet(bytes: { number }): buffer
	local out: buffer = buffer.create(#bytes)
	for index: number, byte: number in bytes do
		buffer.writeu8(out, index - 1, byte)
	end
	return out
end

-- A list that keeps every failure a module reports
local function recorded(module: any): { Report }
	local reports: { Report } = {}

	module.onFailure(function (_, kind: string, detail: string)
		table.insert(reports, { kind = kind, detail = detail })
	end)

	return reports
end

local function setup(name: string): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local player: any, transport: Transport = mock:join("Alice")
	local server: any = Generated.module("Server", MODULES[name].server, mock.server)
	local client: any = Generated.module("Client", MODULES[name].client, transport)
	local names: { [string]: boolean } = {}

	for _, side: any in { server, client } do
		for _, registry: any in { side.events, side.functions } do
			for key: string in registry do
				names[key] = true
			end
		end
	end

	return {
		mock = mock,
		player = player,
		transport = transport,
		server = server,
		client = client,
		hash = tonumber(MODULES[name].server:match("hash = (0x%x+)")) :: number,
		names = names,
		failures = { server = recorded(server), client = recorded(client) },
	}
end

-- Enough steps for a server fire to wait out the client's handshake and arrive, or for a call to come back
local function steps(mock: Mock)
	mock:step()
	mock:step()
	mock:step()
end

-- Runs one step on a thread of its own, so a listener that yields in it is resumed only after a frame has passed
local function across(mock: Mock)
	local thread: thread = coroutine.create(function ()
		mock:step()
	end)

	coroutine.resume(thread)
	mock:step()
	coroutine.resume(thread)
end

-- A failure of a message names it once: the text before the first colon is its registry name, never twice over
local function named(report: Report?, kind: string, name: string)
	local found: Report = assert(report, `no {kind} failure was reported`)

	expect(found.kind).is(kind)
	expect(found.detail:match("^(.-): ")).is(name)
	expect(found.detail:sub(1, 2 * #name + 4)).never_is(`{name}: {name}: `)
end

-- Every failure of a kind names no message, so nothing routes it to a message's owner
local function unnamed(harness: Harness, reports: { Report }, kind: string)
	local count: number = 0

	for _, report: Report in reports do
		if report.kind == kind then
			count += 1
			expect(harness.names).never_has_key(report.detail:match("^(.-): ") or report.detail)
		end
	end

	expect(count > 0).is(true)
end

describe("Failures", function ()
	describe("on the server", function ()
		test("a rate on an event and on a function names the message", function ()
			local exports: Harness = setup("Exports")
			local functions: Harness = setup("Functions")
			local results: { string } = {}

			exports.server.rate("Ping", 1)
			exports.client.Ping.fire()
			exports.client.Ping.fire()
			steps(exports.mock)

			functions.server.Echo.on(function (_, value: number): number
				return value
			end)
			functions.server.rate("Echo", 1)

			for index: number = 1, 2 do
				task.spawn(function ()
					local ok: boolean, value: any = functions.client.Echo.invoke(index)
					table.insert(results, `{ok} {value}`)
				end)
			end

			steps(functions.mock)

			named(exports.failures.server[1], "rate", "Ping")
			named(functions.failures.server[1], "rate", "Echo")
			expect(table.concat(results, ",")).is("true 1,false rate limited")
		end)

		test("a decode inline and inside a shared pair names the message once", function ()
			local events: Harness = setup("Events")
			local records: Harness = setup("Records")
			local stack: { [string]: any } = { item = "a", quantity = OUT_OF_RANGE }

			events.client.Input.fire(WRONG_DIR, true)
			records.client.Records.fire({ x = 1, y = "", z = true }, {}, stack, { version = 1, stacks = {} })
			steps(events.mock)
			steps(records.mock)

			named(events.failures.server[1], "decode", "Input")
			named(records.failures.server[1], "decode", "Records")
			expect(events.failures.server[1].detail).is("Input: Input.dir: out of range")
			expect(records.failures.server[1].detail).is("Records: Stack.quantity: out of range")
		end)

		test("a listener's error and its yield name the event", function ()
			local harness: Harness = setup("Events")

			-- An error that names its own event already is passed on as it is, never named a second time
			harness.server.Ready.on(function ()
				error("Ready: boom", 0)
			end)
			harness.server.Sync.on(function ()
				coroutine.yield()
			end)

			harness.client.Ready.fire()
			harness.client.Sync.fire(1)
			harness.mock:step()
			across(harness.mock)

			named(harness.failures.server[1], "listener", "Ready")
			named(harness.failures.server[2], "listener", "Sync")
			expect(harness.failures.server[2].detail).is("Sync: a sync listener yielded")
		end)

		test("a handler's error names the function, and its caller gets exactly its text in either mode", function ()
			local harness: Harness = setup("Functions")
			local results: { string } = {}

			harness.server.Echo.on(function ()
				error("boom")
			end)
			harness.server.Inventory.Transfer.on(function ()
				error("boom", 0)
			end)

			task.spawn(function ()
				local ok: boolean, reason: any = harness.client.Echo.invoke(1)
				table.insert(results, `{ok} {reason}`)
			end)

			local promise = harness.client.Inventory.Transfer.invoke(1, 2, 3)
			steps(harness.mock)

			named(harness.failures.server[1], "handler", "Echo")
			named(harness.failures.server[2], "handler", "Inventory.Transfer")
			expect(table.concat(results, ",")).is("false boom")
			expect(`{promise.settled[1]} {promise.settled[2]}`).is("false boom")
		end)

		test("a refused structured return names the function, and its caller gets the refusal alone", function ()
			local harness: Harness = setup("Example")

			harness.server.Inventory.Transfer.on(function (): (boolean, string?)
				return true, string.rep("x", LONG_REASON)
			end)

			local promise = harness.client.Inventory.Transfer.invoke("bag", "chest", 1, 1)
			steps(harness.mock)

			named(harness.failures.server[1], "handler", "Inventory.Transfer")
			expect(harness.failures.server[1].detail).is(
				"Inventory.Transfer: Inventory.Transfer.reason: length out of range"
			)
			expect(promise.settled[2]).is("Inventory.Transfer.reason: length out of range")
		end)

		test("a queue overflow names the event", function ()
			local harness: Harness = setup("Events")

			for _ = 1, QUEUE + 1 do
				harness.client.Ready.fire()
			end

			steps(harness.mock)

			named(harness.failures.server[1], "queue", "Ready")
		end)

		test(
			"a packet before the handshake, an unknown id, a wrong hash, the packet rate, the cap and departed name none",
			function ()
				local early: Harness = setup("Events")
				local wrong: Harness = setup("Events")
				local harness: Harness = setup("Events")
				local slow: any = harness.mock:join("Slow") -- No client, so what is fired at them is held step after step
				local half: number = MAX_OUTGOING // (2 * SYNC_BYTES)

				early.transport.reliable(nil, packet({ READY }))
				wrong.transport.reliable(nil, handshake(WRONG_HASH))
				steps(early.mock)
				steps(wrong.mock)
				wrong.server.Sync.fire(wrong.player, 1)

				-- Past the cap in one frame for a player who has handshaken, and over three for one held from the start
				for _ = 1, 2 * half + 1 do
					early.server.Sync.fire(early.player, 1)
				end
				for _ = 1, half do
					harness.server.Sync.fire(slow, 1)
				end

				early.mock:step()
				harness.mock:step()
				harness.transport.reliable(nil, packet({ UNKNOWN_ID }))
				harness.mock:step()

				for _ = 1, MAX_PACKETS + PAST_RATE do
					harness.transport.reliable(nil, buffer.create(0))
				end
				for _ = 1, half + 1 do
					harness.server.Sync.fire(slow, 1)
				end

				harness.mock:step()
				harness.mock:leave(harness.player)
				harness.server.Sync.fire(harness.player, 1)

				expect(early.failures.server[1].detail).is("before the handshake")
				expect(harness.failures.server[1].detail).is(`unknown message {UNKNOWN_ID}`)
				unnamed(early, early.failures.server, "packet")
				unnamed(harness, harness.failures.server, "packet")
				unnamed(wrong, wrong.failures.server, "handshake")
				unnamed(harness, harness.failures.server, "rate")
				unnamed(early, early.failures.server, "outgoing")
				unnamed(harness, harness.failures.server, "outgoing")
				unnamed(wrong, wrong.failures.server, "departed")
				unnamed(harness, harness.failures.server, "departed")
			end
		)
	end)

	describe("on the client", function ()
		test("a decode named once by its reader, one named by a reply's field and one inside a shared pair", function ()
			local events: Harness = setup("Events")
			local reply: Harness = setup("Example")
			local patch: Harness = setup("Example")
			local stack: { [string]: any } = { item = "a", quantity = OUT_OF_RANGE }

			-- A Sync with no value after its id, then a reply to slot 1 whose reason is too long, both straight from the server
			events.mock.server.reliable(events.player, packet({ 1 }))
			reply.mock.server.reliable(reply.player, packet({ 2, 1, 0, 0, 2, LONG_REASON }))
			patch.server.Inventory.Patch.fire(patch.player, { version = 1, set = { [1] = stack }, cleared = {} })

			for _, harness: Harness in { events, reply, patch } do
				steps(harness.mock)
			end

			expect(events.failures.client[1].detail).is("Sync: truncated")
			expect(reply.failures.client[1].detail).is(
				"Inventory.Transfer: Inventory.Transfer.reason: length out of range"
			)
			expect(patch.failures.client[1].detail).is("Inventory.Patch: Stack.quantity: out of range")
			named(reply.failures.client[1], "decode", "Inventory.Transfer")
			named(patch.failures.client[1], "decode", "Inventory.Patch")
		end)

		test("a listener's error and its yield, and a queue overflow, name the event", function ()
			local harness: Harness = setup("Events")
			local queued: Harness = setup("Events")

			harness.client.Sync.on(function (value: number)
				if value == 1 then
					error("boom")
				end

				coroutine.yield()
			end)

			harness.server.Sync.fire(harness.player, 1)
			harness.server.Sync.fire(harness.player, 2)
			harness.mock:step()
			harness.mock:step()
			across(harness.mock)

			for value: number = 1, QUEUE + 1 do
				queued.server.Sync.fire(queued.player, value)
			end

			steps(queued.mock)

			named(harness.failures.client[1], "listener", "Sync")
			named(harness.failures.client[2], "listener", "Sync")
			named(queued.failures.client[1], "queue", "Sync")
			expect(harness.failures.client[2].detail).is("Sync: a sync listener yielded")
		end)

		test("an unknown id and a reliable frame past maxPacket name no message", function ()
			local harness: Harness = setup("Events")

			harness.mock.server.reliable(harness.player, packet({ UNKNOWN_ID }))

			for _ = 1, MAX_PACKET // 2 do
				harness.client.Sync.fire(1)
			end

			steps(harness.mock)

			unnamed(harness, harness.failures.client, "packet")
			unnamed(harness, harness.failures.client, "outgoing")
			expect(harness.failures.client[1].detail).is("over maxPacket, a message was dropped")
		end)
	end)
end)
