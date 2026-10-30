--[[
    Proves the byte-threshold flush over hand-built schema tables: any
    frame on which one target's unsent bytes reach flushBytes flushes, on
    any send and under manualReplication, while a quiet frame keeps its
    batch and a held state never counts
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

local FLUSH_BYTES: number = 3 -- The threshold, which three bytes for one target reach and one byte does not
local EVERY: number = 4 -- A cadence no case reaches before the threshold does

-- A server's schema table with no messages, at the compiler's defaults but for the threshold and the changes given
local function schema(changes: { [string]: any }): Schema
	local options: { [string]: any } = {
		flush = EVERY,
		flushBytes = FLUSH_BYTES,
		manualReplication = false,
		maxPacket = 8192,
		maxPacketsPerSecond = 240,
		maxOutgoing = 262144,
		unreliableBudget = 900,
	}

	for name: string, value: any in changes do
		options[name] = value
	end

	return {
		version = Volt.version,
		hash = 0,
		scope = "Test",
		side = "server",
		idBytes = 1,
		options = options,
		messages = {},
		outgoing = {},
	}
end

-- A packet behind the byte naming the default stream, as a schema with a channel opens every one
local function opened(packet: buffer): buffer
	local out: buffer = buffer.create(buffer.len(packet) + 1)

	buffer.copy(out, 1, packet)

	return out
end

describe("Flushing", function ()
	test("flushes at the first frame that reaches it, and a quiet frame keeps its batch", function ()
		local mock = Volt.mock(task.spawn)
		local alice, client = mock:join("Alice")
		local runtime: Runtime = Volt.start(schema({}), mock.server)
		local got: { number } = {}

		client.receive(function (_, packet: buffer)
			table.insert(got, buffer.len(packet))
		end)

		runtime:packet(alice, handshake(0), nil)
		runtime:target(alice)
		runtime.reliable.allocate(FLUSH_BYTES)

		mock:step() -- Frame 1 reaches it
		mock:step()
		expect(table.concat(got, ",")).is(`{FLUSH_BYTES}`)

		runtime.reliable.allocate(1)

		mock:step() -- Frame 3 keeps the one byte
		expect(table.concat(got, ",")).is(`{FLUSH_BYTES}`)

		mock:step() -- Frame 4 is the flush-th
		mock:step()
		expect(table.concat(got, ",")).is(`{FLUSH_BYTES},1`)
	end)

	test("still flushes under manualReplication", function ()
		local mock = Volt.mock(task.spawn)
		local alice, client = mock:join("Alice")
		local runtime: Runtime = Volt.start(schema({ manualReplication = true }), mock.server)
		local got: number = 0

		client.receive(function ()
			got += 1
		end)

		runtime:packet(alice, handshake(0), nil)
		runtime:target(alice)
		runtime.reliable.allocate(FLUSH_BYTES - 1)

		mock:step()
		mock:step()
		expect(got).is(0)

		runtime.reliable.allocate(1)

		mock:step()
		mock:step()
		expect(got).is(1)
	end)

	for _, send: string in { "reliable", "stream", "unreliable" } do
		test(`counts a target's {send} state`, function ()
			local mock = Volt.mock(task.spawn)
			local alice, client = mock:join("Alice")
			local channelled: Schema = schema({})

			channelled.streams = { "Bulk" }

			local runtime: Runtime = Volt.start(channelled, mock.server)
			local sends: { [string]: any } =
				{ reliable = runtime.reliable, stream = runtime.streams[1], unreliable = runtime.unreliable }
			local got: number = 0

			client.receive(function ()
				got += 1
			end)

			runtime:packet(alice, opened(handshake(0)), nil)
			runtime:target(alice, 1)
			sends[send].allocate(FLUSH_BYTES)

			mock:step()
			mock:step()

			expect(got).is(1)
		end)
	end

	test("holds a held state aside, since the flush could not send it", function ()
		local mock = Volt.mock(task.spawn)
		local alice = mock:join("Alice")
		local bob, other = mock:join("Bob")
		local runtime: Runtime = Volt.start(schema({}), mock.server)
		local got: number = 0

		other.receive(function ()
			got += 1
		end)

		runtime:packet(bob, handshake(0), nil)
		runtime:target(alice)
		runtime.reliable.allocate(FLUSH_BYTES)
		runtime:target(bob)
		runtime.reliable.allocate(1)

		mock:step()
		mock:step()

		expect(got).is(0)
	end)
end)
