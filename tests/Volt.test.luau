--[[
    Proves the runtime a generated module starts: the version check, the
    states every player gets and loses, the target a fire writes into,
    the flush cadence over the Heartbeat and by hand, and the client's
    one target
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Runtime = Volt.Runtime
type Schema = Volt.Schema

-- A schema table with no messages on one side, with the options the runtime reads
local function schema(side: string, options: { [string]: any }?, version: string?): Schema
	return {
		version = version or Volt.version,
		hash = 0,
		scope = "Test",
		side = side,
		idBytes = 1,
		options = options or { flush = 1, manualReplication = false, unreliableBudget = 900 },
		messages = {},
		outgoing = {},
	}
end

describe("Volt", function ()
	test("refuses a schema from another compiler version", function ()
		local mock = Volt.mock(task.spawn)
		local ok: boolean, message: any = pcall(Volt.start, schema("server", nil, "0.2.0"), mock.server)

		expect(ok).is(false)
		expect(tostring(message):find("compiled by Volt 0.2.0 and the runtime is 0.1.0", 1, true) ~= nil).is(true)
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

	test("points both sends at the scratch states for a broadcast", function ()
		local mock = Volt.mock(task.spawn)
		local alice = mock:join("Alice")
		local runtime: Runtime = Volt.start(schema("server"), mock.server)

		runtime:target(alice)

		expect(runtime:target(nil)).is(true)
		expect(runtime.reliable.current == runtime.reliable.scratch).is(true)
		expect(runtime.unreliable.current == runtime.unreliable.scratch).is(true)
	end)

	test("flushes every flush-th Heartbeat, to the player the bytes were written for", function ()
		local mock = Volt.mock(task.spawn)
		local alice, client = mock:join("Alice")
		local _, other = mock:join("Bob")
		local options: { [string]: any } = { flush = 2, manualReplication = false, unreliableBudget = 900 }
		local runtime: Runtime = Volt.start(schema("server", options), mock.server)
		local got: { number } = {}
		local others: number = 0

		client.receive(function (_, packet: buffer)
			table.insert(got, buffer.len(packet))
		end)
		other.receive(function ()
			others += 1
		end)

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
		local options: { [string]: any } = { flush = 1, manualReplication = true, unreliableBudget = 900 }
		local runtime: Runtime = Volt.start(schema("server", options), mock.server)
		local got: number = 0

		client.receive(function ()
			got += 1
		end)

		runtime:target(alice)
		runtime.reliable.allocate(3)

		mock:step()
		mock:step()

		expect(got).is(0)

		runtime:flush()
		mock:step()

		expect(got).is(1)
	end)

	test("sends a client's bytes to the server as that player, one packet per reliability", function ()
		local mock = Volt.mock(task.spawn)
		local alice, client = mock:join("Alice")
		local runtime: Runtime = Volt.start(schema("client"), client)
		local from: any = nil
		local sizes: { number } = {}

		mock.server.receive(function (player: any, packet: buffer)
			from = player
			table.insert(sizes, buffer.len(packet))
		end)

		runtime.reliable.allocate(2)
		runtime.unreliable.allocate(4)

		mock:step()
		mock:step()

		expect(from).is(alice)
		expect(table.concat(sizes, ",")).is("2,4")
	end)
end)
