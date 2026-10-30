--[[
    Proves what a per-player budget does to unreliable messages, over the
    mock and the generated modules: each is kept while the count and what
    the flush has kept are under it, the rest go unsent and are reported
    once a flush with their count, and the default handler stays silent;
    and that a module's flushBytes reaches the runtime
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Budgeted = require("./Budgeted")
local Generated = require("./Generated")
local Served = require("./Served")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect
local connected = Budgeted.connected

type Bot = Volt.Bot
type Harness = Budgeted.Harness
type Mock = Volt.Mock
type Runtime = Volt.Runtime
type Stats = Volt.Stats

local BROADCASTS: string = fs.readFile("tests/Schemas/Broadcasts.volt")
local BELOW_EVERY_FRAME: number = Budgeted.belowEveryFrame
local DAMAGE_BYTES: number = Budgeted.damageBytes
local TWO_SPRAYS: number = 4 -- A budget a first Spray's 3 bytes leave room under, for a second and no third

describe("Budget drops", function ()
	test("a message fired while the count is over reaches no listener and is reported once, with the count", function ()
		local harness: Harness = connected("Broadcasts")
		local heard: number = 0

		harness.client.Spray.on(function ()
			heard += 1
		end)
		harness.runtime:budget(BELOW_EVERY_FRAME)

		harness.server.Spray.fire(harness.alice, 1, 2)
		harness.mock:step()
		harness.mock:step()

		expect(heard).is(1)

		harness.server.Spray.fire(harness.alice, 1, 2)
		harness.mock:step()
		harness.mock:step()

		expect(heard).is(1)
		expect(table.concat(harness.failures, ",")).is("budget: over the budget, unreliable messages dropped: 1")
		expect(harness.runtime:stats(harness.alice).failures.budget).is(1)
		expect(harness.runtime:stats().failures.budget).is(1)
	end)

	test("the generated member sets the budget a drop is judged by, and clears it", function ()
		local harness: Harness = connected("Broadcasts")
		local heard: number = 0

		harness.client.Spray.on(function ()
			heard += 1
		end)
		harness.server.budget(BELOW_EVERY_FRAME)

		for _ = 1, 2 do
			harness.server.Spray.fire(harness.alice, 1, 2)
			harness.mock:step()
			harness.mock:step()
		end

		expect(heard).is(1)
		expect(table.concat(harness.failures, ",")).is("budget: over the budget, unreliable messages dropped: 1")

		harness.server.budget(nil)
		harness.server.Spray.fire(harness.alice, 1, 2)
		harness.mock:step()
		harness.mock:step()

		expect(heard).is(2)
	end)

	test("a message is kept while the count and what the flush has kept are under, and the rest go", function ()
		local harness: Harness = connected("Broadcasts")
		local heard: number = 0
		local stats: Stats = harness.runtime:stats(harness.alice)

		harness.client.Spray.on(function ()
			heard += 1
		end)
		harness.runtime:budget(TWO_SPRAYS)

		for _ = 1, 3 do
			harness.server.Spray.fire(harness.alice, 1, 2)
		end

		harness.mock:step()
		harness.mock:step()

		expect(heard).is(2)
		expect(stats.packetsOut).is(1)
		expect(stats.messagesOut).is(3)
		expect(table.concat(harness.failures, ",")).is("budget: over the budget, unreliable messages dropped: 1")
	end)

	test("a message the cap dropped is an outgoing failure and no budget drop", function ()
		local harness: Harness = connected("Capped")
		local heard: number = 0

		harness.client.Spray.on(function ()
			heard += 1
		end)
		harness.runtime:budget(TWO_SPRAYS + 1)

		-- Eight bytes fit two: the third is dropped when the fourth begins, and the fourth at the flush
		for _ = 1, 4 do
			harness.server.Spray.fire(harness.alice, 1, 2)
		end

		harness.mock:step()
		harness.mock:step()

		expect(heard).is(2)
		expect(harness.runtime:stats(harness.alice).failures.outgoing).is(2)
		expect(harness.runtime:stats(harness.alice).failures.budget).is(nil)
	end)

	test("the runtime's own handler counts a drop and stays silent", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local server: any, runtime: Runtime = Generated.module("Server", Served.modules.Broadcasts.server, mock.server)
		local bot: Bot = mock:addBot("Helper")

		runtime:budget(BELOW_EVERY_FRAME)

		for _ = 1, 2 do
			server.Spray.fire(bot, 1, 2)
			server.Spray.fire(bot, 1, 2)
			mock:step()
		end

		expect(runtime:stats(bot).failures.budget).is(2)
		expect((runtime :: any)._players[bot].warned.budget).is(nil)
	end)
end)

describe("A module's flushBytes", function ()
	test("flushes once a target's bytes reach it, between the frames flush names", function ()
		local text: string = `option flush = 4\noption flushBytes = {2 * DAMAGE_BYTES}\n{BROADCASTS}`
		local _, module: string = Generated.modules("Broadcasts", text)
		local mock: Mock = Volt.mock(task.spawn)
		local server: any, runtime: Runtime = Generated.module("Server", module, mock.server)
		local bot: Bot = mock:addBot("Helper")
		local stats: Stats = runtime:stats(bot)

		server.Damage.fire(bot, Budgeted.hit(1))
		mock:step()

		expect(stats.packetsOut).is(0)

		server.Damage.fire(bot, Budgeted.hit(2))
		mock:step()

		expect(stats.packetsOut).is(1)
		expect(stats.bytesOut).is(2 * DAMAGE_BYTES)
	end)
end)
