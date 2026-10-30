--[[
    Proves the failure detail contract for a failure of one message on
    the client, over the generated modules: its detail begins with the
    message's registry name and a colon exactly once, an instance that
    never arrives, a @delta message with no baseline and a dictionary id
    or message the client cannot take included
--]]

--!strict
local Suite = require("./Suite")
local Environment = require("./Environment")
local Failures = require("./Failures")
local outwait = require("./Outwait")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect
local across = Failures.across
local named = Failures.named
local packet = Failures.packet
local setup = Failures.setup
local steps = Failures.steps

local Instance = Environment.Instance

type Harness = Failures.Harness

local QUEUE: number = Failures.queue
local LONG_REASON: number = Failures.longReason
local OUT_OF_RANGE: number = Failures.outOfRange
local NOT_TEXT: { number } = Failures.notText
local LINE: number = 1 -- The id Console's line reaches the client with
local ECHO: number = 1 -- The id Echo's reply reaches the client with
local UNKNOWN_STATUS: number = 7 -- Past the 3 a reply's status reaches
local BRIEF: number = 0.001 -- Awaited's Brief's timeout
local VITALS: number = 1 -- The id Deltas' vitals reaches the client with
local PICKED: number = 1 -- The id Dictionary's picked reaches the client with
local DICTIONARY: number = 0 -- The id the dictionary message reaches the client with
local NO_ENTRY: number = 9 -- A dictionary id the server never gave a string
local SECOND: number = 2 -- The id of the dictionary's second entry, which an empty dictionary cannot take first

describe("Failures", function ()
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

		test("a reply with a status no reply carries names the function", function ()
			local harness: Harness = setup("Functions")

			-- Echo's reply to slot 1, straight from the server, with a status past the last a reply carries
			harness.mock.server.reliable(harness.player, packet({ ECHO, 1, 0, UNKNOWN_STATUS }))
			steps(harness.mock)

			named(harness.failures.client[1], "decode", "Echo")
			expect(harness.failures.client[1].detail).is("Echo: unknown status 7")
		end)

		test("a handler's error names the function, with no player", function ()
			local harness: Harness = setup("Prompts")

			harness.client.Camera.Aim.on(function ()
				error("boom")
			end)

			harness.server.Camera.Aim.invoke(harness.player)
			steps(harness.mock)

			named(harness.failures.client[1], "handler", "Camera.Aim")
			expect(harness.failures.client[1].player).is(nil)
		end)

		test("a decode of text that is not UTF-8 inside a shared pair names the event", function ()
			local harness: Harness = setup("Console")
			local length: number = #NOT_TEXT

			-- Built by hand, since the server's pair checks the text in every build: the id, Line's u16 length and
			-- its bytes, then Kind's flag byte
			harness.mock.server.reliable(harness.player, packet({ LINE, length, 0, NOT_TEXT[1], NOT_TEXT[2], 0 }))
			steps(harness.mock)

			named(harness.failures.client[1], "decode", "Decree.line")
			expect(harness.failures.client[1].detail).is("Decree.line: Decree.Line: invalid UTF-8")
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

		test("an instance that never arrives, and one that arrives late of another class, name the event", function ()
			local brief: Harness = setup("Awaited")
			local spawned: Harness = setup("Awaited")
			local never: any, part: any = Instance.new("Part"), Instance.new("Part")

			-- The unchecked server sends a Part as Spawned's model, which the client refuses only once it arrives
			brief.mock:hide(never)
			spawned.mock:hide(part)
			brief.server.World.Brief.fire(brief.player, never)
			spawned.server.World.Spawned.fire(spawned.player, part, 1)
			steps(brief.mock)
			steps(spawned.mock)
			outwait(brief.mock, BRIEF)
			spawned.mock:reveal(part)
			spawned.mock:step()

			named(brief.failures.client[1], "resolve", "World.Brief")
			named(spawned.failures.client[1], "decode", "World.Spawned")
			expect(spawned.failures.client[1].detail).is(
				"World.Spawned: World.Spawned.model: expected AwaitedInstance(Model)"
			)
		end)

		test(
			"a @delta patch with no baseline, an unknown dictionary id and an early dictionary entry name theirs",
			function ()
				local deltas: Harness = setup("Deltas")
				local unknown: Harness = setup("Dictionary")
				local early: Harness = setup("Dictionary")

				-- Straight from the server: a vitals whose empty mask patches a value the client never had, a picked
				-- naming an id no entry has, and a dictionary message of one entry, "A", that would be the second
				deltas.mock.server.reliable(deltas.player, packet({ VITALS, 0 }))
				unknown.mock.server.reliable(unknown.player, packet({ PICKED, NO_ENTRY, 0, NO_ENTRY, 0 }))
				early.mock.server.reliable(early.player, packet({ DICTIONARY, SECOND, 0, 1, 0, 1, 0x41 }))

				for _, harness: Harness in { deltas, unknown, early } do
					steps(harness.mock)
				end

				named(deltas.failures.client[1], "decode", "vitals")
				named(unknown.failures.client[1], "decode", "picked")
				named(early.failures.client[1], "decode", "Volt.dictionary")
				expect(deltas.failures.client[1].detail).is("vitals: no baseline")
				expect(unknown.failures.client[1].detail).is("picked: picked.item: unknown dictionary id")
				expect(early.failures.client[1].detail).is("Volt.dictionary: out of order")
			end
		)
	end)
end)
