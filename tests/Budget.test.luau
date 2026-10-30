--[[
    Proves what a per-player budget does to reliable messages, over the
    mock and the generated modules: each waits and is never dropped, a
    deferral always ends, nothing it holds back becomes an outgoing drop,
    each stream defers alone, and a scope with no budget is never held back
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local Budgeted = require("./Budgeted")
local Generated = require("./Generated")
local Served = require("./Served")
local Streamed = require("./Streamed")
local handshake = require("./Handshake")
local Volt = require("@volt")
local Config = require("@volt/Config/Runtime")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect
local connected = Budgeted.connected
local hearing = Budgeted.hearing
local hit = Budgeted.hit
local pending = Budgeted.pending

type Bot = Volt.Bot
type Box = Streamed.Box
type Harness = Budgeted.Harness
type Hit = Budgeted.Hit
type Mock = Volt.Mock
type Runtime = Volt.Runtime
type Stats = Volt.Stats

local BELOW_EVERY_FRAME: number = Budgeted.belowEveryFrame
local DAMAGE_BYTES: number = Budgeted.damageBytes
local AMPLE: number = 1e9 -- A budget no test's bytes come near
local WRONG_HASH: number = 0xBAD
local FREE: number = 100 -- What the unbudgeted runtime's targets start from, so one client can tell the two apart
local PENDING: string = "pending" -- A call that has not come back

describe("Budget", function ()
	test(
		"a message waits step after step once the first packet has gone, then goes in fire order when cleared",
		function ()
			local harness: Harness = connected("Broadcasts")
			local heard: { number } = hearing(harness)
			local stats: Stats = harness.runtime:stats(harness.alice)

			harness.runtime:budget(BELOW_EVERY_FRAME)
			harness.server.Damage.fire(harness.alice, hit(0))
			harness.mock:step()

			for target: number = 1, 3 do
				harness.server.Damage.fire(harness.alice, hit(target))
				harness.mock:step()
			end

			harness.mock:step()

			expect(table.concat(heard, ",")).is("0")
			expect(stats.packetsOut).is(1)
			expect(pending(harness.runtime, harness.alice)).is(3 * DAMAGE_BYTES)

			harness.runtime:budget(nil)
			harness.mock:step()
			harness.mock:step()

			expect(table.concat(heard, ",")).is("0,1,2,3")
			expect(stats.packetsOut).is(4)
			expect(stats.bytesOut).is(4 * DAMAGE_BYTES)
			expect(stats.messagesOut).is(4)
			expect(pending(harness.runtime, harness.alice)).is(0)
			expect(#harness.failures).is(0)
		end
	)

	test("the generated member sets the budget and clears it", function ()
		local harness: Harness = connected("Broadcasts")
		local heard: { number } = hearing(harness)

		harness.server.budget(BELOW_EVERY_FRAME)
		harness.server.Damage.fire(harness.alice, hit(1))
		harness.mock:step()
		harness.server.Damage.fire(harness.alice, hit(2))
		harness.mock:step()
		harness.mock:step()

		expect(table.concat(heard, ",")).is("1")

		harness.server.budget(nil)
		harness.mock:step()
		harness.mock:step()

		expect(table.concat(heard, ",")).is("1,2")
	end)

	test("a message goes once the count is under a raised budget, in fire order", function ()
		local harness: Harness = connected("Broadcasts")
		local heard: { number } = hearing(harness)

		harness.runtime:budget(BELOW_EVERY_FRAME)
		harness.server.Damage.fire(harness.alice, hit(0))
		harness.mock:step()
		harness.server.Damage.fire(harness.alice, hit(1))
		harness.mock:step()
		harness.runtime:budget(AMPLE)
		harness.server.Damage.fire(harness.alice, hit(2))
		harness.mock:step()
		harness.mock:step()

		expect(table.concat(heard, ",")).is("0,1,2")
	end)

	test("the design's worked example: the backlog passes maxOutgoing and nothing reports outgoing", function ()
		local harness: Harness = connected("Capped")
		local heard: { number } = hearing(harness)
		local sprays: number = 0
		local stats: Stats = harness.runtime:stats(harness.alice)

		harness.client.Spray.on(function ()
			sprays += 1
		end)
		harness.runtime:budget(BELOW_EVERY_FRAME)

		-- Frame 1 sends, as the first packet and with a count of 0
		harness.server.Damage.fire(harness.alice, hit(1))
		harness.mock:step()

		-- Frame 2 is cut into a waiting packet of 8 bytes
		harness.server.Damage.fire(harness.alice, hit(2))
		harness.server.Damage.fire(harness.alice, hit(3))
		harness.mock:step()

		expect(pending(harness.runtime, harness.alice)).is(2 * DAMAGE_BYTES)

		-- 8 waiting and 8 more would pass maxOutgoing, so frame 3 fires the waiting packet, then its own
		harness.server.Damage.fire(harness.alice, hit(4))
		harness.server.Damage.fire(harness.alice, hit(5))
		harness.server.Spray.fire(harness.alice, 7, 9)
		harness.mock:step()
		harness.mock:step()

		expect(table.concat(heard, ",")).is("1,2,3,4,5")
		expect(sprays).is(0)
		expect(table.concat(harness.failures, ",")).is("budget: over the budget, unreliable messages dropped: 1")
		expect(stats.packetsOut).is(3)
		expect(stats.bytesOut).is(5 * DAMAGE_BYTES)
		expect(stats.messagesOut).is(6)
	end)

	test("a reply that waits is answered once the budget clears, never with timeout", function ()
		local harness: Harness = connected("Functions")
		local first: Box = { line = PENDING }
		local second: Box = { line = PENDING }

		harness.server.Echo.on(function (_, value: number): number
			return value * 2
		end)
		harness.runtime:budget(BELOW_EVERY_FRAME)

		Streamed.into(first, harness.client.Echo.invoke, 7)
		Served.held(harness.mock)

		Streamed.into(second, harness.client.Echo.invoke, 9)
		Served.held(harness.mock)
		Served.held(harness.mock)

		expect(first.line).is("true 14")
		expect(second.line).is(PENDING)

		harness.runtime:budget(nil)
		harness.mock:step()
		harness.mock:step()

		expect(second.line).is("true 18")
		expect(#harness.failures).is(0)
	end)

	test("a reply that waits stays behind the events its handler fired", function ()
		local harness: Harness = connected("Streams")
		local heard: { number } = {}
		local atReturn: string = PENDING

		harness.client.Notice.on(function (value: number)
			table.insert(heard, value)
		end)
		harness.server.Ask.on(function (player: any, value: number): number
			harness.server.Notice.fire(player, 1)
			harness.server.Notice.fire(player, 2)
			return value
		end)
		harness.runtime:budget(BELOW_EVERY_FRAME)
		harness.server.Notice.fire(harness.alice, 0)
		harness.mock:step()

		task.spawn(function ()
			harness.client.Ask.invoke(5)
			atReturn = table.concat(heard, ",")
		end)

		Served.held(harness.mock)
		Served.held(harness.mock)

		expect(atReturn).is(PENDING)

		harness.runtime:budget(nil)
		harness.mock:step()
		harness.mock:step()

		expect(atReturn).is("0,1,2")
	end)

	test("a channel's stream defers on its own and keeps its order, its packets keeping their byte", function ()
		local harness: Harness = connected("Streams")
		local chats: { string } = {}
		local notices: { number } = {}

		harness.client.Chat.on(function (value: string)
			table.insert(chats, value)
		end)
		harness.client.Notice.on(function (value: number)
			table.insert(notices, value)
		end)
		harness.runtime:budget(BELOW_EVERY_FRAME)

		harness.server.Chat.fire(harness.alice, "a")
		harness.mock:step()

		-- The channel has opened and waits; the default stream's first packet goes all the same
		harness.server.Chat.fire(harness.alice, "b")
		harness.server.Notice.fire(harness.alice, 1)
		harness.mock:step()
		harness.server.Chat.fire(harness.alice, "c")
		harness.mock:step()
		harness.mock:step()

		expect(table.concat(chats, ",")).is("a")
		expect(table.concat(notices, ",")).is("1")

		harness.runtime:budget(nil)
		harness.mock:step()
		harness.mock:step()

		expect(table.concat(chats, ",")).is("a,b,c")
		expect(#harness.failures).is(0)
	end)

	test("a stamped packet that waited reads the flush that sent it, on either stream", function ()
		local harness: Harness = connected("Streams")
		local times: { string } = {}

		harness.client.Chat.on(function (value: string)
			table.insert(times, `{value} at {harness.client.serverTime()}`)
		end)
		harness.client.Notice.on(function (value: number)
			table.insert(times, `{value} at {harness.client.serverTime()}`)
		end)
		harness.runtime:budget(BELOW_EVERY_FRAME)

		harness.mock.time = 10
		harness.server.Notice.fire(harness.alice, 1)
		harness.mock:step()
		harness.server.Chat.fire(harness.alice, "a")
		harness.mock:step()

		harness.mock.time = 20
		harness.server.Notice.fire(harness.alice, 2)
		harness.server.Chat.fire(harness.alice, "b")
		harness.mock:step()

		harness.mock.time = 30
		harness.runtime:budget(nil)
		harness.mock:step()
		harness.mock:step()

		expect(table.concat(times, ",")).is("1 at 10,a at 10,2 at 30,b at 30")
	end)

	test("a dictionary message goes ahead of a waiting packet, as it fires", function ()
		local harness: Harness = connected("Dictionary")
		local heard: { string } = {}
		local stats: Stats = harness.runtime:stats(harness.alice)

		harness.client.picked.on(function (item: string, title: string)
			table.insert(heard, `{item} {title}`)
		end)
		harness.runtime:budget(BELOW_EVERY_FRAME)

		-- The dictionary message and the first packet
		harness.server.picked.fire(harness.alice, "Sword", "Scout")
		harness.mock:step()

		harness.server.picked.fire(harness.alice, "Bow", "Archer")
		harness.mock:step()
		harness.mock:step()

		expect(stats.packetsOut).is(2)

		harness.runtime:budget(nil)
		harness.mock:step()
		harness.mock:step()

		expect(table.concat(heard, ",")).is("Sword Scout,Bow Archer")
		expect(stats.packetsOut).is(4)
		expect(harness.client.stats().failures.decode).is(nil)
	end)

	test("what waits goes with a player who leaves, unreported, and with one a failed handshake refuses", function ()
		local harness: Harness = connected("Broadcasts")
		local bot: Bot = harness.mock:addBot("Helper")

		harness.runtime:budget(BELOW_EVERY_FRAME)

		for _, player: any in { harness.alice, bot } do
			harness.server.Damage.fire(player, hit(1))
		end

		harness.mock:step()

		for _, player: any in { harness.alice, bot } do
			harness.server.Damage.fire(player, hit(2))
		end

		harness.mock:step()

		expect(pending(harness.runtime, harness.alice)).is(DAMAGE_BYTES)
		expect(pending(harness.runtime, bot)).is(DAMAGE_BYTES)

		harness.mock:leave(harness.alice)
		harness.runtime:packet(bot, handshake(WRONG_HASH), nil)
		harness.mock:step()

		expect(pending(harness.runtime, harness.alice)).is(0)
		expect(pending(harness.runtime, bot)).is(0)
		expect(harness.runtime:stats(bot).packetsOut).is(1)
		expect(#harness.failures).is(1)
		expect(harness.failures[1]:match("^%a+")).is("handshake")
	end)

	test("an unbudgeted runtime on the same hub is never held back, and the window ends a deferral", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local free: any, _, freeRuntime: Runtime = Served.serve("Broadcasts", mock) -- First, so it flushes first in a step
		local budgeted: any, failures: { string }, runtime: Runtime = Served.serve("Broadcasts", mock)
		local bot: Bot = mock:addBot("Helper")
		local client: any = Generated.module("Client", Served.modules.Broadcasts.client, mock:connectBot(bot))
		local heard: { number } = {}

		client.Damage.on(function (value: Hit)
			if value.target < FREE then
				table.insert(heard, value.target)
			end
		end)
		runtime:budget(BELOW_EVERY_FRAME)

		for target: number = 1, 4 do
			free.Damage.fire(bot, hit(FREE + target))
			budgeted.Damage.fire(bot, hit(target))
			mock:step()

			expect(freeRuntime:stats(bot).packetsOut).is(target)
			expect(runtime:stats(bot).packetsOut).is(1)
		end

		expect(table.concat(heard, ",")).is("1")
		expect(pending(runtime, bot)).is(3 * DAMAGE_BYTES)

		task.wait(Config.trafficSeconds)

		-- The unbudgeted runtime flushes first, so the count is still over when the budgeted one is judged
		free.Damage.fire(bot, hit(FREE))
		mock:step()

		expect(table.concat(heard, ",")).is("1,2,3,4")
		expect(runtime:stats(bot).packetsOut).is(4)
		expect(pending(runtime, bot)).is(0)
		expect(#failures).is(0)
	end)
end)
