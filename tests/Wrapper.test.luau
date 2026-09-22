--[[
    Proves what the wrapper plugs into, over the generated modules: the
    registry names every entry, a hook before a send or after a receive
    sees its target or player and the arguments and its veto is counted,
    a name no side has is refused, a rate changes while the game runs,
    and an exported type writes to a buffer and reads back
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Environment = require("./Environment")
local Generated = require("./Generated")
local golden = require("./Expected")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock

-- A server and one client over one mock, each running the generated module of its side
type Harness = { mock: Mock, player: any, server: any, client: any }

local Instance = Environment.Instance

local EVENTS_CLIENT: string, EVENTS_SERVER: string =
	Generated.modules("Events", fs.readFile("tests/Schemas/Events.volt"))
local BROADCASTS_CLIENT: string, BROADCASTS_SERVER: string =
	Generated.modules("Broadcasts", fs.readFile("tests/Schemas/Broadcasts.volt"))
local FUNCTIONS_CLIENT: string, FUNCTIONS_SERVER: string =
	Generated.modules("Functions", fs.readFile("tests/Schemas/Functions.volt"))
local EXPORTS_CLIENT: string, EXPORTS_SERVER: string, EXPORTS_TYPES: string =
	Generated.modules("Exports", fs.readFile("tests/Schemas/Exports.volt"))
local SIDES: { { name: string, text: string } } = {
	{ name = "Client", text = EXPORTS_CLIENT },
	{ name = "Server", text = EXPORTS_SERVER },
	{ name = "Types", text = EXPORTS_TYPES },
}

-- The modules of both sides over a fresh mock, the server quiet about failures since a rate miss would warn
local function setup(client: string, server: string): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local player, transport = mock:join("Alice")
	local serverNet: any = Generated.module("Server", server, mock.server)

	serverNet.onFailure(function () end)

	return {
		mock = mock,
		player = player,
		server = serverNet,
		client = Generated.module("Client", client, transport),
	}
end

-- One step flushes what was fired and the next delivers it
local function exchange(mock: Mock)
	mock:step()
	mock:step()
end

-- One step flushes a call, the next delivers it and flushes the reply, the last delivers the reply
local function roundTrip(mock: Mock)
	mock:step()
	mock:step()
	mock:step()
end

describe("Wrapper", function ()
	for _, side in SIDES do
		test(`renders the Exports {side.name:lower()} module as its golden file`, function ()
			expect(golden("tests/Golden/Exports", side.name, side.text)).is(side.text)
		end)
	end

	test("the registry holds every event, function and exported type by its full name, as its entry", function ()
		local events: Harness = setup(EVENTS_CLIENT, EVENTS_SERVER)
		local broadcasts: Harness = setup(BROADCASTS_CLIENT, BROADCASTS_SERVER)
		local functions: Harness = setup(FUNCTIONS_CLIENT, FUNCTIONS_SERVER)
		local exports: Harness = setup(EXPORTS_CLIENT, EXPORTS_SERVER)

		expect(broadcasts.server.events["Match.Start"] == broadcasts.server.Match.Start).is(true)
		expect(events.client.events.Sync == events.client.Sync).is(true)
		expect((next(events.server.functions))).is(nil)
		expect(functions.client.functions["Inventory.Transfer"] == functions.client.Inventory.Transfer).is(true)
		expect(exports.server.exports["Inventory.Kind"] == exports.server.Inventory.Kind).is(true)
		expect(exports.client.exports.Save == exports.client.Save).is(true)
		expect(exports.client.events.Ping == exports.client.Ping).is(true)
	end)

	describe("before a send", function ()
		test("the client's hook sees no target and the arguments, and its veto skips the send and counts", function ()
			local harness: Harness = setup(EVENTS_CLIENT, EVENTS_SERVER)
			local seen: { string } = {}
			local heard: number = 0

			harness.server.Input.on(function ()
				heard += 1
			end)
			harness.client.hooks.beforeSend("Input", function (target: any, dir: number, jump: boolean): boolean
				table.insert(seen, `{target} {dir} {jump}`)
				return dir < 5
			end)

			harness.client.Input.fire(3, true)
			harness.client.Input.fire(7, false)
			exchange(harness.mock)

			expect(table.concat(seen, ",")).is("nil 3 true,nil 7 false")
			expect(heard).is(1)
			expect(harness.client.stats().rejected).is(1)
		end)

		test("the server's hook sees the player on a fire, the list or set on a broadcast, nil for everyone", function ()
			local harness: Harness = setup(BROADCASTS_CLIENT, BROADCASTS_SERVER)
			local player: any = harness.player
			local players: { any } = { player }
			local set: { [any]: true } = { [player] = true }
			local seen: { any } = {}
			local heard: number = 0

			harness.client.Damage.on(function ()
				heard += 1
			end)
			harness.server.hooks.beforeSend("Damage", function (target: any, hit: { [string]: number }): boolean
				table.insert(seen, target == nil and "nil" or target)
				return hit.amount ~= 0
			end)

			harness.server.Damage.fire(player, { target = 1, amount = 0 })
			harness.server.Damage.fireList(players, { target = 1, amount = 1 })
			harness.server.Damage.fireAll({ target = 1, amount = 2 })
			harness.server.Damage.fireExcept(player, { target = 1, amount = 0 })
			harness.server.Damage.fireSet(set, { target = 1, amount = 3 })
			exchange(harness.mock)

			expect(seen[1] == player and seen[2] == players and seen[5] == set).is(true)
			expect(`{seen[3]} {seen[4]}`).is("nil nil")
			expect(heard).is(3)
			expect(harness.server.stats().rejected).is(2)
			expect(harness.server.stats(player).rejected).is(1)
		end)

		test(
			"registering again replaces the hook, nil clears it, and a name this side does not send is refused",
			function ()
				local harness: Harness = setup(EVENTS_CLIENT, EVENTS_SERVER)
				local heard: number = 0

				harness.server.Ready.on(function ()
					heard += 1
				end)
				harness.client.hooks.beforeSend("Ready", function (): boolean
					return false
				end)
				harness.client.hooks.beforeSend("Ready", function (): boolean
					return true
				end)
				harness.client.Ready.fire()
				harness.client.hooks.beforeSend("Ready", nil)
				harness.client.Ready.fire()
				exchange(harness.mock)

				expect(heard).is(2)

				local ok: boolean, message: any = pcall(harness.server.hooks.beforeSend, "Ready", function (): boolean
					return true
				end)

				expect(ok).is(false)
				expect(tostring(message):find("Ready: not an event this side sends", 1, true) ~= nil).is(true)
			end
		)
	end)

	describe("after a receive", function ()
		test(
			"the hook over every message runs first, then the message's own, each with the player and arguments",
			function ()
				local harness: Harness = setup(EVENTS_CLIENT, EVENTS_SERVER)
				local seen: { string } = {}

				harness.server.Chat.on(function () end)
				harness.server.hooks.afterReceive(nil, function (player: any, ...: any): boolean
					table.insert(seen, `all {player.Name} {select("#", ...)}`)
					return true
				end)
				harness.server.hooks.afterReceive("Chat", function (player: any, text: string): boolean
					table.insert(seen, `own {player.Name} {text}`)
					return true
				end)

				harness.client.Chat.fire("hi")
				harness.client.Ready.fire()
				exchange(harness.mock)

				expect(table.concat(seen, ",")).is("all Alice 1,own Alice hi,all Alice 0")
			end
		)

		test("a veto drops the message before any listener, counted for the player, and the packet goes on", function ()
			local harness: Harness = setup(EVENTS_CLIENT, EVENTS_SERVER)
			local heard: { string } = {}

			harness.server.Chat.on(function (_, text: string)
				table.insert(heard, text)
			end)
			harness.server.Ready.on(function ()
				table.insert(heard, "ready")
			end)
			harness.server.hooks.afterReceive("Chat", function (_, text: string): boolean
				return text ~= "spam"
			end)

			harness.client.Chat.fire("spam")
			harness.client.Ready.fire()
			harness.client.Chat.fire("hello")
			exchange(harness.mock)

			expect(table.concat(heard, ",")).is("ready,hello")
			expect(harness.server.stats(harness.player).rejected).is(1)
			expect((next(harness.server.stats().failures))).is(nil)
		end)

		test("a vetoed call never reaches its handler and is not answered", function ()
			local harness: Harness = setup(FUNCTIONS_CLIENT, FUNCTIONS_SERVER)
			local served: number = 0
			local line: string = "pending"

			harness.server.Echo.on(function (_, value: number): number
				served += 1
				return value
			end)
			harness.server.hooks.afterReceive("Echo", function (): boolean
				return false
			end)

			task.spawn(function ()
				local ok: boolean, value: any = harness.client.Echo.invoke(4)
				line = `{ok} {value}`
			end)

			roundTrip(harness.mock)

			expect(served).is(0)
			expect(line).is("pending")
			expect(harness.server.stats(harness.player).rejected).is(1)
		end)

		test("a name this side does not hear is refused, on the client too", function ()
			local harness: Harness = setup(EVENTS_CLIENT, EVENTS_SERVER)
			local function allow(): boolean
				return true
			end

			local serverOk: boolean, serverMessage: any = pcall(harness.server.hooks.afterReceive, "Nope", allow)
			local clientOk: boolean, clientMessage: any = pcall(harness.client.hooks.afterReceive, "Input", allow)

			expect(serverOk).is(false)
			expect(tostring(serverMessage):find("Nope: not a message this side hears", 1, true) ~= nil).is(true)
			expect(clientOk).is(false)
			expect(tostring(clientMessage):find("Input: not a message this side hears", 1, true) ~= nil).is(true)
		end)
	end)

	describe("rate", function ()
		test("changes an event's rate and burst at once, and does nothing on the client", function ()
			local events: Harness = setup(EVENTS_CLIENT, EVENTS_SERVER)
			local broadcasts: Harness = setup(BROADCASTS_CLIENT, BROADCASTS_SERVER)
			local ready: number, damage: number = 0, 0

			events.server.Ready.on(function ()
				ready += 1
			end)
			broadcasts.client.Damage.on(function ()
				damage += 1
			end)
			events.server.rate("Ready", 1, 2)
			broadcasts.client.rate("Damage", 1)

			for _ = 1, 3 do
				events.client.Ready.fire()
				broadcasts.server.Damage.fire(broadcasts.player, { target = 1, amount = 1 })
			end

			exchange(events.mock)
			exchange(broadcasts.mock)

			expect(ready).is(2)
			expect(damage).is(3)
			expect(events.server.stats(events.player).failures.rate).is(1)
		end)

		test("limits a function too, and refuses a name this side does not hear", function ()
			local harness: Harness = setup(FUNCTIONS_CLIENT, FUNCTIONS_SERVER)
			local results: { string } = {}

			harness.server.Ping.on(function () end)
			harness.server.rate("Ping", 1, 1)

			for index: number = 1, 2 do
				task.spawn(function ()
					local ok: boolean, reason: any = harness.client.Ping.invoke()
					results[index] = `{ok} {reason}`
				end)
			end

			roundTrip(harness.mock)

			expect(table.concat(results, ",")).is("true nil,false rate limited")

			local ok: boolean, message: any = pcall(harness.server.rate, "Nope", 1)

			expect(ok).is(false)
			expect(tostring(message):find("Nope: not a message this side hears", 1, true) ~= nil).is(true)
		end)
	end)

	describe("an exported type", function ()
		test("writes a value to a buffer with its side array, and the other side reads it back", function ()
			local harness: Harness = setup(EXPORTS_CLIENT, EXPORTS_SERVER)
			local owner = Instance.new("Folder")
			local packet: buffer, side: { any }? =
				harness.client.Save.write({ version = 7, names = { "a", "bc" }, owner = owner })
			local read: { [string]: any } = harness.server.Save.read(packet, side)
			local kind: buffer, none: { any }? = harness.client.Inventory.Kind.write("Chest")

			expect(read.version).is(7)
			expect(table.concat(read.names, ",")).is("a,bc")
			expect(read.owner == owner).is(true)
			expect(none).is(nil)
			expect(harness.server.Inventory.Kind.read(kind)).is("Chest")
		end)

		test("a refused write raises with nothing counted, and the client still sends after it", function ()
			local harness: Harness = setup(EXPORTS_CLIENT, EXPORTS_SERVER)
			local heard: number = 0

			harness.server.Ping.on(function ()
				heard += 1
			end)

			local ok: boolean, message: any = pcall(harness.client.Save.write, { version = 70000, names = {} })

			expect(ok).is(false)
			expect(message).is("Save.version: expected u16")

			harness.client.Ping.fire()
			exchange(harness.mock)

			expect(heard).is(1)
			expect(harness.client.stats().messagesOut).is(2) -- The handshake and the ping, and nothing for the write
		end)

		test("a read without the side array its instance sits in is refused", function ()
			local harness: Harness = setup(EXPORTS_CLIENT, EXPORTS_SERVER)
			local packet: buffer =
				harness.client.Save.write({ version = 1, names = {}, owner = Instance.new("Folder") })
			local ok: boolean, message: any = pcall(harness.server.Save.read, packet)

			expect(ok).is(false)
			expect(tostring(message):find("Save.owner: expected Instance", 1, true) ~= nil).is(true)
		end)
	end)
end)
