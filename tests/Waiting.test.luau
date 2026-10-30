--[[
    Proves the client's waits for awaited instances over the mock, with
    readers written by hand as generated ones read: a message naming one
    that has not arrived waits while others go on, is read again once it
    arrives, in the order read, and past its deadline is a resolve failure
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local Waiters = require("./Waiters")
local packet = require("./Packet")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Client = Waiters.Client
type Harness = Waiters.Harness
type Mock = Volt.Mock
type Report = Waiters.Report
type Runtime = Volt.Runtime
type Transport = Volt.Transport

local SPAWNED: number = Waiters.spawned
local PLAIN: number = Waiters.plain
local PAIR: number = Waiters.pair

local instance = Waiters.instance
local setup = Waiters.setup
local send = Waiters.send

describe("Waiting", function ()
	test("delivers a message at once when the instance it names is here, with the instance itself", function ()
		local harness: Harness = setup()
		local model: any = instance("A")
		local heard: any = nil

		harness.runtime:on(SPAWNED, function (found: any)
			heard = found
		end)

		send(harness, packet({ SPAWNED, harness.reference(model), 0, 0, 0, 5 }))

		expect(table.concat(harness.seen, ",")).is("A 5")
		expect(rawequal(heard, model)).is(true)
		expect(#harness.failures).is(0)
	end)

	test("holds a message whose instance has not arrived while the packet's next message goes on", function ()
		local harness: Harness = setup()
		local model: any = instance("A")
		local id: number = harness.reference(model)

		harness.mock:hide(model)
		send(harness, packet({ SPAWNED, id, 0, 0, 0, 5, PLAIN, 1 }))
		harness.mock:step()

		expect(table.concat(harness.seen, ",")).is("plain 1")

		harness.mock:reveal(model)
		harness.mock:step()

		expect(table.concat(harness.seen, ",")).is("plain 1,A 5")
		expect(#harness.failures).is(0)
	end)

	test("delivers those waiting on one instance in the order read, and on two in the order they arrive", function ()
		local harness: Harness = setup()
		local first: any, second: any = instance("A"), instance("B")
		local a: number, b: number = harness.reference(first), harness.reference(second)

		harness.mock:hide(first)
		harness.mock:hide(second)
		send(harness, packet({ SPAWNED, a, 0, 0, 0, 1, SPAWNED, b, 0, 0, 0, 2, SPAWNED, a, 0, 0, 0, 3 }))

		harness.mock:reveal(second)
		harness.mock:step()

		expect(table.concat(harness.seen, ",")).is("B 2")

		harness.mock:reveal(first)
		harness.mock:step()

		expect(table.concat(harness.seen, ",")).is("B 2,A 1,A 3")
	end)

	test("holds a message naming an id another waits on behind it, even once the instance is visible", function ()
		local harness: Harness = setup()
		local model: any = instance("A")
		local id: number = harness.reference(model)

		harness.mock:hide(model)
		send(harness, packet({ SPAWNED, id, 0, 0, 0, 1 }))

		-- Visible now, though the client hears of it only at the next step
		harness.mock:reveal(model)
		harness.runtime:packet(nil, packet({ SPAWNED, id, 0, 0, 0, 2 }), nil)

		expect(#harness.seen).is(0)

		send(harness, packet({ SPAWNED, id, 0, 0, 0, 3 }))

		expect(table.concat(harness.seen, ",")).is("A 1,A 2,A 3")
	end)

	test("delivers a message naming two instances, one of them twice, once, after the last arrives", function ()
		local harness: Harness = setup()
		local first: any, second: any = instance("A", "Part"), instance("B", "Part")
		local a: number, b: number = harness.reference(first), harness.reference(second)

		harness.mock:hide(first)
		harness.mock:hide(second)
		send(harness, packet({ PAIR, a, 0, 0, 0, b, 0, 0, 0, PAIR, b, 0, 0, 0, b, 0, 0, 0 }))

		harness.mock:reveal(first)
		harness.mock:step()

		expect(#harness.seen).is(0)

		harness.mock:reveal(second)
		harness.mock:step()

		expect(table.concat(harness.seen, ",")).is("A B,B B")
	end)

	test("a message read again that finds an instance gone since its first read waits for it again", function ()
		local harness: Harness = setup()
		local first: any, second: any = instance("A", "Part"), instance("B", "Part")
		local a: number, b: number = harness.reference(first), harness.reference(second)

		harness.mock:hide(second)
		send(harness, packet({ PAIR, a, 0, 0, 0, b, 0, 0, 0 }))

		harness.mock:hide(first)
		harness.mock:reveal(second)
		harness.mock:step()

		expect(#harness.seen).is(0)

		harness.mock:reveal(first)
		harness.mock:step()

		expect(`{table.concat(harness.seen, ",")} {#harness.failures}`).is("A B 0")
	end)

	test("keeps a waiting message's own bytes and slots, and reads them again from the first", function ()
		local harness: Harness = setup()
		local visible: any, hidden: any = instance("A"), instance("B")
		local a: number, b: number = harness.reference(visible), harness.reference(hidden)

		harness.mock:hide(hidden)
		send(harness, packet({ SPAWNED, a, 0, 0, 0, 1, SPAWNED, b, 0, 0, 0, 2 }), { "first", "second" })

		harness.mock:reveal(hidden)
		harness.mock:step()

		expect(table.concat(harness.seen, ",")).is("A 1 by first,B 2 by second")
	end)

	test("drops a message past its deadline at a flush as one resolve failure named for it, never delivered", function ()
		local harness: Harness = setup({ timeout = 0 })
		local first: any, second: any = instance("A"), instance("B")
		local a: number, b: number = harness.reference(first), harness.reference(second)

		harness.mock:hide(first)
		harness.mock:hide(second)
		send(harness, packet({ SPAWNED, a, 0, 0, 0, 1, PAIR, a, 0, 0, 0, b, 0, 0, 0 }))
		harness.mock:step()

		harness.mock:reveal(first)
		harness.mock:reveal(second)
		harness.mock:step()

		local failures: { Report } = harness.failures

		expect(#harness.seen).is(0)
		expect(`{#failures} {failures[1].player} {failures[1].kind} {failures[2].kind}`).is("2 nil resolve resolve")
		expect(failures[1].detail).is("World.Spawned: instance 1 did not arrive within 0 seconds")
		expect(failures[2].detail).is("World.Pair: instances 1, 2 did not arrive within 0 seconds")
		expect(harness.runtime:stats(nil).failures.resolve).is(2)

		for _, report: Report in failures do
			local name: string = report.detail:match("^(.-): ") :: string
			expect(report.detail:sub(1, 2 * #name + 4) ~= `{name}: {name}: `).is(true)
		end
	end)

	test("a message read again whose instance is of another class is a decode failure named for it", function ()
		local harness: Harness = setup()
		local part: any = instance("P", "Part")

		harness.mock:hide(part)
		send(harness, packet({ SPAWNED, harness.reference(part), 0, 0, 0, 1 }))

		harness.mock:reveal(part)
		harness.mock:step()

		local report: Report = harness.failures[1]

		expect(`{#harness.seen} {#harness.failures} {report.player} {report.kind}`).is("0 1 nil decode")
		expect(report.detail).is("World.Spawned: World.Spawned.model: expected AwaitedInstance(Model)")
	end)

	test("a decode failure part way through an awaited message leaves no id that holds back the next one", function ()
		local harness: Harness = setup()
		local hidden: any, visible: any = instance("A"), instance("B")
		local a: number, b: number = harness.reference(hidden), harness.reference(visible)

		harness.mock:hide(hidden)
		harness.mock.server.reliable(harness.alice, packet({ SPAWNED, a, 0, 0, 0, 0 }))
		send(harness, packet({ SPAWNED, b, 0, 0, 0, 2 }))

		expect(table.concat(harness.seen, ",")).is("B 2")
		expect(`{#harness.failures} {harness.failures[1].kind}`).is("1 decode")
		expect(harness.failures[1].detail).is("World.Spawned: World.Spawned.health: out of range")
	end)

	test("a message read again goes through the hook after a receive and into a polled event's queue", function ()
		local harness: Harness = setup({ mode = "Polling" })
		local model: any = instance("A")
		local hooked: { string } = {}

		harness.runtime.afterReceive("World.Spawned", function (_: any, found: any): boolean
			table.insert(hooked, found and found.Name or "nil")
			return true
		end)

		harness.mock:hide(model)
		send(harness, packet({ SPAWNED, harness.reference(model), 0, 0, 0, 3 }))

		expect(`{#hooked} {harness.runtime:iter(SPAWNED)()}`).is("0 nil")

		harness.mock:reveal(model)
		harness.mock:step()

		local index: number, found: any, health: number = harness.runtime:iter(SPAWNED)()

		expect(`{table.concat(hooked, ",")} {index} {found.Name} {health}`).is("A 1 A 3")
	end)

	test("a message read again is delivered under the stamp of the packet it came in", function ()
		local harness: Harness = setup({ stamp = true })
		local model: any = instance("A")

		harness.mock:hide(model)
		send(harness, Waiters.stamped(10, { SPAWNED, harness.reference(model), 0, 0, 0, 1 }))
		send(harness, Waiters.stamped(20, { PLAIN, 2 }))

		harness.mock:reveal(model)
		harness.mock:step()

		expect(table.concat(harness.seen, ",")).is("plain 2 at 20,A 1 at 10")
		expect(harness.runtime:serverTime()).is(20)
	end)

	test("a bot's client side resolves every instance at once, hidden from players or not", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local bot: Volt.Bot = mock:addBot("Helper")
		local client: Client = Waiters.start(mock:connectBot(bot), {})
		local model: any = instance("A")
		local id: number = assert(mock.server.reference, "the mock's server gives instances ids")(model)

		mock:hide(model)
		mock.server.reliable(bot, packet({ SPAWNED, id, 0, 0, 0, 5 }))
		mock:step()

		expect(table.concat(client.seen, ",")).is("A 5")
	end)

	test("a server gives an instance one id for its life and another instance its own", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local server: Runtime = Volt.start(Waiters.schema("server", {}), mock.server)
		local first: any, second: any = instance("A"), instance("B")
		local ids: string = `{server.instanceId(first)} {server.instanceId(first)} {server.instanceId(second)}`

		expect(ids).is("1 1 2")
	end)

	test("instanceId over a transport that keeps no references raises its message", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local bare: Transport = table.clone(mock.server)

		bare.reference = nil

		local server: Runtime = Volt.start(Waiters.schema("server", {}), bare)
		local ok: boolean, message: any = pcall(server.instanceId, instance("A"))

		expect(ok).is(false)
		expect(tostring(message)).is("Volt: this transport carries no instance references")
	end)
end)
