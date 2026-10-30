--[[
    Proves the runtime a generated module starts: the version check, the
    states every player gets and loses, the target a fire writes into,
    the flush cadence over the Heartbeat and by hand, the client's one
    target, whose reliable frame never outgrows what the server reads, and
    a budget over hand-built schema tables
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local handshake = require("./Handshake")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Runtime = Volt.Runtime
type Schema = Volt.Schema

-- The options the runtime reads, at the compiler's defaults
local OPTIONS: { [string]: any } = {
	flush = 1,
	manualReplication = false,
	maxPacket = 8192,
	maxPacketsPerSecond = 240,
	maxOutgoing = 262144,
	unreliableBudget = 900,
}

local SMALL_PACKET: number = 16 -- A server's maxPacket two of the largest messages below cannot share
local LARGEST: number = 8 -- A client's largest reliable message, which fits beside the handshake alone
local HANDSHAKE_BYTES: number = 5 -- What opens a client's first frame
local FRAME_BYTES: number = 3 -- What a frame writes in the budget's cases
local ONE_BYTE: number = 1 -- A budget in bytes a second that any packet at all takes the count past

-- A schema table with no messages on one side, with the options the runtime reads
local function schema(side: string, options: { [string]: any }?, version: string?): Schema
	return {
		version = version or Volt.version,
		hash = 0,
		scope = "Test",
		side = side,
		idBytes = 1,
		options = options or OPTIONS,
		messages = {},
		outgoing = {},
	}
end

describe("Volt", function ()
	test("refuses a schema from another compiler version, naming its scope with no source position", function ()
		local mock = Volt.mock(task.spawn)
		local ok: boolean, message: any = pcall(Volt.start, schema("server", nil, "0.2.0"), mock.server)

		expect(ok).is(false)
		expect(message).is(`Volt: Test's schema was compiled by Volt 0.2.0 and the runtime is {Volt.version}`)
	end)

	test("gives states to every player present and joining, and frees them when they leave", function ()
		local mock = Volt.mock(task.spawn)
		local alice = mock:join("Alice")
		local runtime: Runtime = Volt.start(schema("server"), mock.server)
		local bob = mock:join("Bob")
		local departed: number = 0

		runtime:onFailure(function (_, kind: string)
			if kind == "departed" then
				departed += 1
			end
		end)

		expect(runtime:target(alice)).is(true)
		expect(runtime.reliable.current == runtime.reliable.scratch).is(false)
		expect(runtime:target(bob)).is(true)

		mock:leave(bob)

		expect(runtime:target(bob)).is(false)
		expect(departed).is(1)
		expect(runtime:target(alice)).is(true)
	end)

	test("raises for a target of no player, leaving both sends where they pointed", function ()
		local mock = Volt.mock(task.spawn)
		local alice = mock:join("Alice")
		local runtime: Runtime = Volt.start(schema("server"), mock.server)

		runtime:target(alice)

		local ok: boolean = pcall(runtime.target, runtime, nil)

		expect(ok).is(false)
		expect(runtime.reliable.current == runtime.reliable.scratch).is(false)
		expect(runtime.unreliable.current == runtime.unreliable.scratch).is(false)
	end)

	test("flushes every flush-th Heartbeat, to the player the bytes were written for", function ()
		local mock = Volt.mock(task.spawn)
		local alice, client = mock:join("Alice")
		local _, other = mock:join("Bob")
		local options: { [string]: any } = table.clone(OPTIONS)
		options.flush = 2

		local runtime: Runtime = Volt.start(schema("server", options), mock.server)
		local got: { number } = {}
		local others: number = 0

		client.receive(function (_, packet: buffer)
			table.insert(got, buffer.len(packet))
		end)
		other.receive(function ()
			others += 1
		end)

		-- Handed straight to the runtime, so the hold lets go of her bytes without a frame passing
		runtime:packet(alice, handshake(0), nil)
		runtime:target(alice)
		runtime.reliable.allocate(3)

		mock:step() -- The first frame does not flush
		mock:step() -- The second does, and the packet arrives on the step after
		expect(#got).is(0)

		mock:step()
		expect(table.concat(got, ",")).is("3")
		expect(others).is(0)
	end)

	test("leaves flushing to the game under manualReplication", function ()
		local mock = Volt.mock(task.spawn)
		local alice, client = mock:join("Alice")
		local options: { [string]: any } = table.clone(OPTIONS)
		options.manualReplication = true

		local runtime: Runtime = Volt.start(schema("server", options), mock.server)
		local got: number = 0

		client.receive(function ()
			got += 1
		end)

		runtime:packet(alice, handshake(0), nil)
		runtime:target(alice)
		runtime.reliable.allocate(3)

		mock:step()
		mock:step()

		expect(got).is(0)

		runtime:flush()
		mock:step()

		expect(got).is(1)
	end)

	test(
		"sends a client's bytes to the server as that player, one packet per reliability, the handshake first",
		function ()
			local mock = Volt.mock(task.spawn)
			local alice, client = mock:join("Alice")
			local runtime: Runtime = Volt.start(schema("client"), client)
			local from: any = nil
			local first: buffer? = nil
			local sizes: { number } = {}

			mock.server.receive(function (player: any, packet: buffer)
				from = player
				first = first or packet
				table.insert(sizes, buffer.len(packet))
			end)

			runtime.reliable.allocate(2)
			runtime.unreliable.allocate(4)

			mock:step()
			mock:step()

			expect(from).is(alice)
			expect(table.concat(sizes, ",")).is("7,4")
			expect(buffer.readu8(assert(first, "nothing reached the server"), 0)).is(0)
		end
	)

	test("caps a client's reliable frame at maxPacket, dropping the message past it and never the handshake", function ()
		local mock = Volt.mock(task.spawn)
		local _, client = mock:join("Alice")
		local options: { [string]: any } = table.clone(OPTIONS)

		options.maxPacket = SMALL_PACKET

		local runtime: Runtime = Volt.start(schema("client", options), client)
		local arrived: { string } = {}
		local failures: { string } = {}

		runtime:onFailure(function (_, kind: string, detail: string)
			table.insert(failures, `{kind}: {detail}`)
		end)
		mock.server.receive(function (_, packet: buffer)
			table.insert(arrived, `{buffer.len(packet)} {buffer.readu8(packet, 0)}`)
		end)

		-- The handshake and the first fit what the server reads, and the second would take the frame past it
		runtime.reliable.begin(LARGEST)
		runtime.reliable.begin(LARGEST)

		mock:step()
		mock:step()

		expect(table.concat(arrived, ",")).is(`{HANDSHAKE_BYTES + LARGEST} 0`)
		expect(table.concat(failures, ",")).is("outgoing: over maxPacket, a message was dropped")
	end)

	describe("budget", function ()
		test(
			"a player's count from another runtime leaves the first packet going at once, and the second waits",
			function ()
				local mock = Volt.mock(task.spawn)
				local alice = mock:join("Alice")
				local other: Runtime = Volt.start(schema("server"), mock.server)
				local runtime: Runtime = Volt.start(schema("server"), mock.server)
				local sentAtHandshake: number? = nil

				runtime:budget(ONE_BYTE)

				other:packet(alice, handshake(0), nil)
				other:target(alice)
				other.reliable.allocate(FRAME_BYTES)
				other:flush()

				-- Held for her handshake here, and that flush lets it go before the callback runs
				runtime:target(alice)
				runtime.reliable.allocate(FRAME_BYTES)
				runtime:onHandshake(function ()
					sentAtHandshake = runtime:stats(alice).packetsOut
				end)
				runtime:packet(alice, handshake(0), nil)
				runtime:flush()

				expect(sentAtHandshake).is(1)

				runtime.reliable.allocate(FRAME_BYTES)
				runtime:flush()

				local _, written: number = runtime:traffic(alice)

				expect(runtime:stats(alice).packetsOut).is(1)
				expect(written).is(FRAME_BYTES)
			end
		)

		test("an unreliable state keeps the run its budget leaves room for, the first message with its slot", function ()
			local mock = Volt.mock(task.spawn)
			local alice, client = mock:join("Alice")
			local runtime: Runtime = Volt.start(schema("server"), mock.server)
			local arrived: { string } = {}
			local failures: { string } = {}

			client.receive(function (_, packet: buffer, side: { any }?)
				table.insert(arrived, `{buffer.len(packet)} {table.concat(side or {}, ",")}`)
			end)
			runtime:onFailure(function (_, kind: string, detail: string)
				table.insert(failures, `{kind}: {detail}`)
			end)

			runtime:packet(alice, handshake(0), nil)
			runtime:budget(ONE_BYTE)
			runtime:target(alice)

			for _, slot: string in { "a", "b", "c" } do
				runtime.unreliable.begin(LARGEST)
				runtime.unreliable.slot(slot)
				runtime.unreliable.mark()
			end

			mock:step()
			mock:step()

			expect(table.concat(arrived, ";")).is(`{LARGEST} a`)
			expect(table.concat(failures, ",")).is("budget: over the budget, unreliable messages dropped: 2")
			expect(runtime:stats(alice).failures.budget).is(1)
		end)

		test("is the server's alone", function ()
			local mock = Volt.mock(task.spawn)
			local _, client = mock:join("Alice")
			local runtime: Runtime = Volt.start(schema("client"), client)
			local ok: boolean = pcall(runtime.budget, runtime, ONE_BYTE)

			expect(ok).is(false)
		end)
	end)
end)
