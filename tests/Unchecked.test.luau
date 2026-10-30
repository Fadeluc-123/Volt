--[[
    Proves that a writer built without write validation that raises part
    way leaves nothing of its message behind, over the mock with modules
    compiled with the option off: a fire of either reliability, a
    broadcast, a @delta fire and its baseline, an invoke from either side
    and an encode, each named for its message; and that a reply is checked
    all the same, through a pair an event walked
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local Volt = require("@volt")
local Config = require("@volt/Config/Runtime")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock

-- A server and two clients over one mock, each running its side's unchecked module, and what the server reported
type Harness = {
	mock: Mock,
	server: any,
	alice: any,
	bob: any,
	failures: { string },
}

local SCHEMAS: { string } = { "Events", "Broadcasts", "Functions", "Exports", "Console", "Prompts", "Deltas" }
local BAD: string = "bad" -- A value no number or table field takes, which a buffer write or an index raises on
local NOT_TEXT: string = string.char(0xFF) -- A byte no UTF-8 text holds
local COMMAND: string = "go" -- Text Console's run takes
local KIND: string = "Info" -- A Kind every line and reply may carry
local REFUSED: string = "Decree.Line: invalid UTF-8" -- What the pair Console's line and run's return share refuses

local MODULES: { [string]: { client: string, server: string } } = {}

for _, name: string in SCHEMAS do
	local source: string = `option writeValidation = false\n{fs.readFile(`tests/Schemas/{name}.volt`)}`
	local client: string, server: string = Generated.modules(name, source)

	MODULES[name] = { client = client, server = server }
end

local function setup(name: string): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local _, alice = mock:join("Alice")
	local _, bob = mock:join("Bob")
	local failures: { string } = {}
	local server: any = Generated.module("Server", MODULES[name].server, mock.server)

	server.onFailure(function (_, kind: string, detail: string)
		table.insert(failures, `{kind} {detail}`)
	end)

	return {
		mock = mock,
		server = server,
		alice = Generated.module("Client", MODULES[name].client, alice),
		bob = Generated.module("Client", MODULES[name].client, bob),
		failures = failures,
	}
end

-- One step flushes what was fired and the next delivers it
local function exchange(mock: Mock)
	mock:step()
	mock:step()
end

-- A raised error as the caller sees it: named for its message first, with Luau's source position cut
local function named(ok: boolean, message: any, expected: string)
	local text: string = tostring(message)

	expect(ok).is(false)
	expect(text:sub(1, #expected)).is(expected)
	expect(text:find(":%d+: ") == nil).is(true)
end

describe("An unchecked writer that raises", function ()
	test("on a reliable fire leaves nothing behind, so the fire after it in the frame arrives alone", function ()
		local harness: Harness = setup("Events")
		local heard: { number } = {}

		harness.server.Sync.on(function (_, value: number)
			table.insert(heard, value)
		end)

		local sent: number = harness.alice.stats().messagesOut
		local ok: boolean, message: any = pcall(harness.alice.Sync.fire, BAD)

		named(ok, message, "Sync: invalid argument")
		expect(harness.alice.stats().messagesOut).is(sent)

		harness.alice.Sync.fire(7)
		exchange(harness.mock)

		expect(table.concat(heard, ",")).is("7")
		expect(#harness.failures).is(0)
	end)

	test("on an unreliable fire leaves nothing behind either", function ()
		local harness: Harness = setup("Events")
		local heard: { string } = {}

		harness.server.Input.on(function (_, dir: number, jump: boolean)
			table.insert(heard, `{dir} {jump}`)
		end)

		local ok: boolean, message: any = pcall(harness.alice.Input.fire, BAD, true)
		named(ok, message, "Input: invalid argument")

		harness.alice.Input.fire(3, false)
		exchange(harness.mock)

		expect(table.concat(heard, ",")).is("3 false")
		expect(#harness.failures).is(0)
	end)

	test("passes a refusal on as it was, uncounted once", function ()
		local harness: Harness = setup("Events")
		local heard: { string } = {}

		harness.server.Chat.on(function (_, text: string)
			table.insert(heard, text)
		end)

		local sent: number = harness.alice.stats().messagesOut
		local ok: boolean, message: any = pcall(harness.alice.Chat.fire, string.rep("x", 65))

		expect(ok).is(false)
		expect(tostring(message)).is("Chat: length out of range")
		expect(harness.alice.stats().messagesOut).is(sent)

		harness.alice.Chat.fire("hi")
		exchange(harness.mock)

		expect(table.concat(heard, ",")).is("hi")
	end)

	test("in a broadcast leaves the scratch state clean for the next", function ()
		local harness: Harness = setup("Broadcasts")
		local heard: { string } = {}

		for _, client: any in { harness.alice, harness.bob } do
			client.Damage.on(function (hit: { target: number, amount: number })
				table.insert(heard, `{hit.target} {hit.amount}`)
			end)
		end

		local ok: boolean, message: any = pcall(harness.server.Damage.fireAll, { target = BAD, amount = 1 })
		named(ok, message, "Damage: invalid argument")

		harness.server.Damage.fireAll({ target = 5, amount = 2 })
		exchange(harness.mock)
		harness.mock:step() -- Held until the clients' handshakes arrive, a step after they are flushed

		expect(table.concat(heard, ",")).is("5 2,5 2")
	end)

	test("in a @delta fire leaves nothing behind and no baseline, so the next fire is masked as before it", function ()
		local harness: Harness = setup("Deltas")
		local player: any = harness.mock.players[1]
		local value: { [string]: any } =
			{ health = 100, stamina = 50, title = "Scout", held = 7, gear = { shield = true, boots = false } }
		local heard: { string } = {}

		harness.alice.vitals.on(function (vitals: { [string]: any })
			table.insert(heard, `{vitals.health} {vitals.stamina}`)
		end)

		harness.server.vitals.fire(player, value)
		exchange(harness.mock)
		harness.mock:step() -- Held until Alice's handshake arrives, a step after it is flushed

		local sent: number = harness.server.stats(player).messagesOut
		local bytes: number = harness.server.stats(player).bytesOut
		local wrong: { [string]: any } = table.clone(value)

		wrong.stamina = BAD

		local ok: boolean, message: any = pcall(harness.server.vitals.fire, player, wrong)

		named(ok, message, "vitals: invalid argument")
		expect(harness.server.stats(player).messagesOut).is(sent)

		-- Kept as the baseline, the wrong stamina would be sent again beside the health: here it is the id, the mask
		-- and health's one byte
		value.health = 90
		harness.server.vitals.fire(player, value)
		exchange(harness.mock)

		expect(harness.server.stats(player).bytesOut - bytes).is(3)
		expect(table.concat(heard, ",")).is("100 50,90 50")
		expect(#harness.failures).is(0)
	end)

	test("in an invoke gives its slot back and sends nothing, so the call after it is answered", function ()
		local harness: Harness = setup("Functions")
		local calls: number = 0
		local answer: string = "pending"

		harness.server.Echo.on(function (_, value: number): number
			calls += 1
			return value * 2
		end)

		local ok: boolean, message: any = pcall(harness.alice.Echo.invoke, BAD)
		named(ok, message, "Echo: invalid argument")

		task.spawn(function ()
			local answered: boolean, value: number = harness.alice.Echo.invoke(21)
			answer = `{answered} {value}`
		end)

		exchange(harness.mock)
		harness.mock:step()

		expect(answer).is("true 42")
		expect(calls).is(1)
		expect(#harness.failures).is(0)
	end)

	test("in a server's invoke leaves nothing in the player's frame and gives the slot back", function ()
		local harness: Harness = setup("Prompts")
		local player: any = harness.mock.players[1]
		local answer: string = "pending"
		local ok: boolean, message: any = true, nil

		harness.alice.Confirm.on(function (title: string, seconds: number): (boolean, string?)
			return true, `{title} {seconds}`
		end)

		-- More calls than a player has slots, each raising once Confirm's id, slot and title length are written
		for _ = 1, Config.playerSlots + 1 do
			ok, message = pcall(harness.server.Confirm.invoke, player, "Sell?", BAD)
		end

		named(ok, message, "Confirm: invalid argument")
		expect(select(2, harness.server.traffic(player))).is(0)

		task.spawn(function ()
			local answered: boolean, accepted: boolean, note: string? =
				harness.server.Confirm.invoke(player, "Sell?", 3)
			answer = `{answered} {accepted} {note}`
		end)

		-- Held until Alice's handshake, so it goes out a step later than a call after it would
		exchange(harness.mock)
		exchange(harness.mock)

		expect(answer).is("true true Sell? 3")
		expect(#harness.failures).is(0)
	end)

	test("in an encode leaves the next encode only its own bytes", function ()
		local harness: Harness = setup("Exports")
		local save: { [string]: any } = { version = 3, names = { "a" } }
		local first: buffer = harness.alice.Save.write(save)

		local ok: boolean, message: any = pcall(harness.alice.Save.write, { version = BAD, names = {} })
		named(ok, message, "Save: invalid argument")

		expect(buffer.tostring(harness.alice.Save.write(save))).is(buffer.tostring(first))
	end)
end)

describe("An unchecked module's reply", function ()
	test("is refused when its text is not UTF-8, though an event walks the pair it shares first", function ()
		local harness: Harness = setup("Console")

		harness.server.Decree.run.on(function (): (string, string)
			return NOT_TEXT, KIND
		end)

		local promise: any = harness.alice.Decree.run.invoke(COMMAND)

		exchange(harness.mock)
		harness.mock:step()

		expect(table.concat(harness.failures, ",")).is(`handler Decree.run: {REFUSED}`)
		expect(`{promise.settled[1]} {promise.settled[2]}`).is(`false {REFUSED}`)

		local ok: boolean, message: any =
			pcall(harness.server.Decree.line.fire, harness.mock.players[1], NOT_TEXT, KIND)

		expect(ok).is(false)
		expect(tostring(message)).is(REFUSED)
	end)
end)
