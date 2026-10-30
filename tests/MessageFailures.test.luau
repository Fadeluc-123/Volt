--[[
    Proves the failure detail contract for a failure of one message on
    the server, over the generated modules: its detail begins with the
    message's registry name and a colon exactly once, a stale ordered
    message included, and a handler's error reaches its caller as exactly
    its text
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local Failures = require("./Failures")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect
local across = Failures.across
local named = Failures.named
local packet = Failures.packet
local setup = Failures.setup
local steps = Failures.steps

type Harness = Failures.Harness

local QUEUE: number = Failures.queue
local LONG_REASON: number = Failures.longReason
local OUT_OF_RANGE: number = Failures.outOfRange
local NOT_TEXT: { number } = Failures.notText
local WRONG_DIR: number = 9 -- Past the 8 Input's dir allows
local CONFIRM: number = 2 -- The id Prompts' Confirm reply reaches the server with
local NEVER_GIVEN: number = 9 -- A slot the server never gave a call
local AIM: number = 1 -- The id Ordered's Aim reaches the server with
local AIM_RATE: number = 2 -- The Aims a second the server allows Alice in the stale case
local ALONE: number = 1 -- The id the one event of Rotations, Layouts and Volumes reaches the server with
local NO_ROTATION: number = 0xFFFFFFFF -- Three kept components that square to 1.5, past the 1 a rotation allows
local TURN_BYTES: number = 27 -- Turn's least size after its id, with no c
local LAYOUTS_BYTES: number = 58 -- Layouts' size after its id
local VOLUMES_BYTES: number = 72 -- Volumes' size after its id
local RANGE: number = 25 -- Where Layouts' c, a NumberRange of two f32s, begins: past the id, a's 16 bytes and b's 8
local CORNER: number = 37 -- Where Volumes' c, a Region3, begins: past the id, a's 24 bytes and b's 12

-- Sends the server one event by hand behind Alice's handshake: its id, then its bytes, zero but where set writes
local function sent(harness: Harness, bytes: number, set: (body: buffer) -> ())
	local body: buffer = buffer.create(1 + bytes)

	buffer.writeu8(body, 0, ALONE)
	set(body)
	harness.mock:step()
	harness.transport.reliable(nil, body)
	steps(harness.mock)
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

		test("a decode of text that is not UTF-8 names the function", function ()
			local harness: Harness = setup("Console")

			-- The client's module checks nothing it writes, so the text reaches the server's reader
			harness.client.Decree.run.invoke(string.char(table.unpack(NOT_TEXT)))
			steps(harness.mock)

			named(harness.failures.server[1], "decode", "Decree.run")
			expect(harness.failures.server[1].detail).is("Decree.run: Decree.run.text: invalid UTF-8")
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

		test("a reply naming a slot never given names the function", function ()
			local harness: Harness = setup("Prompts")

			-- Behind Alice's handshake, Confirm's reply to a slot no call took: the id, the slot, status ok and the flags
			harness.mock:step()
			harness.transport.reliable(nil, packet({ CONFIRM, NEVER_GIVEN, 0, 0, 1 }))
			steps(harness.mock)

			named(harness.failures.server[1], "decode", "Confirm")
			expect(harness.failures.server[1].detail).is(`Confirm: no call in slot {NEVER_GIVEN}`)
		end)

		test("a stale ordered message past its event's rate names the event", function ()
			local harness: Harness = setup("Ordered")
			local heard: number = 0

			harness.server.Aim.on(function ()
				heard += 1
			end)
			harness.server.rate("Aim", AIM_RATE)

			-- Behind Alice's handshake, Aims with sequences 1 and 2 take the rate, so 1 again is stale and past it
			harness.mock:step()
			harness.transport.unreliable(
				nil,
				packet({ AIM, 1, 0, 0, 0, 0, 0, AIM, 2, 0, 0, 0, 0, 0, AIM, 1, 0, 0, 0, 0, 0 })
			)
			steps(harness.mock)

			named(harness.failures.server[1], "rate", "Aim")
			expect(harness.failures.server[1].detail).is(`Aim: over {AIM_RATE} a second`)
			expect(heard).is(AIM_RATE)
		end)

		test(
			"a rotation past one, a range whose least passes its most and an infinite corner name the event",
			function ()
				local rotations: Harness = setup("Rotations")
				local layouts: Harness = setup("Layouts")
				local volumes: Harness = setup("Volumes")

				sent(rotations, TURN_BYTES, function (body: buffer)
					buffer.writeu32(body, 1, NO_ROTATION)
				end)
				sent(layouts, LAYOUTS_BYTES, function (body: buffer)
					buffer.writef32(body, RANGE, 2)
					buffer.writef32(body, RANGE + 4, 1)
				end)
				sent(volumes, VOLUMES_BYTES, function (body: buffer)
					buffer.writef32(body, CORNER, -math.huge)
				end)

				named(rotations.failures.server[1], "decode", "Turn")
				named(layouts.failures.server[1], "decode", "Layouts")
				named(volumes.failures.server[1], "decode", "Volumes")
				expect(rotations.failures.server[1].detail).is("Turn: Turn.a: out of range")
				expect(layouts.failures.server[1].detail).is("Layouts: Layouts.c: out of range")
				expect(volumes.failures.server[1].detail).is("Volumes: Volumes.c: out of range")
			end
		)
	end)
end)
