--[[
    Proves awaited instances end to end over the Awaited schema's modules
    and the mock: a message naming an instance a player lacks waits while
    the rest go on and arrives once it does, a wait past its timeout is a
    resolve failure, and the server keeps ids and refuses bad instances
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Environment = require("./Environment")
local Generated = require("./Generated")
local outwait = require("./Outwait")
local tapped = require("./Tapped")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

local Instance = Environment.Instance
local Vector3 = Environment.Vector3

type Fired = tapped.Fired
type Mock = Volt.Mock
type Transport = Volt.Transport

type Report = { player: any, kind: string, detail: string } -- One failure the client reported, with its player

-- A server and Alice's client over a mock, Alice's handshake read, and what the client heard and reported
type Harness = {
	mock: Mock,
	alice: any,
	server: any,
	client: any,
	heard: { string },
	models: { any }, -- The model each Spawned listener call received, in order
	failures: { Report },
}

local AWAITED: string = fs.readFile("tests/Schemas/Awaited.volt")
local CLIENT: string, SERVER: string = Generated.modules("Awaited", AWAITED)
local BRIEF: number = 0.001 -- Brief's timeout in the schema
local SPAWNED: number = 7 -- A Spawned's bytes: its id, its model's id and its health

-- Unchecked on both sides, since the option is in the hash the handshake compares
local UNCHECKED_CLIENT: string, UNCHECKED_SERVER: string =
	Generated.modules("Awaited", `option writeValidation = false\n{AWAITED}`)

-- The client's listeners log what they hear; the modules are checked unless a test asks, and the server's packets
-- are kept in fired when a test hands it in
local function setup(unchecked: boolean?, fired: { Fired }?): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local alice: any, transport: Transport = mock:join("Alice")
	local serving: Transport = fired and tapped(mock.server, fired) or mock.server
	local server: any = Generated.module("Server", unchecked and UNCHECKED_SERVER or SERVER, serving)
	local client: any = Generated.module("Client", unchecked and UNCHECKED_CLIENT or CLIENT, transport)
	local harness: Harness = {
		mock = mock,
		alice = alice,
		server = server,
		client = client,
		heard = {},
		models = {},
		failures = {},
	}

	client.onFailure(function (player: any, kind: string, detail: string)
		table.insert(harness.failures, { player = player, kind = kind, detail = detail })
	end)

	client.World.Spawned.on(function (model: any, health: number)
		table.insert(harness.heard, `spawned {health}`)
		table.insert(harness.models, model)
	end)

	client.World.Plain.on(function (value: number)
		table.insert(harness.heard, `plain {value}`)
	end)

	-- One step sends Alice's handshake and the next reads it, so what a test fires goes out at its next step
	mock:step()
	mock:step()

	return harness
end

-- One step sends what the server fired and the next delivers it
local function exchange(mock: Mock)
	mock:step()
	mock:step()
end

describe("Awaited instances", function ()
	test("a model not streamed in holds back its message alone, so a plain one fired after it goes first", function ()
		local harness: Harness = setup()
		local model: any = Instance.new("Model")

		harness.mock:hide(model)
		harness.server.World.Spawned.fire(harness.alice, model, 5)
		harness.server.World.Plain.fire(harness.alice, 1)
		exchange(harness.mock)

		expect(table.concat(harness.heard, ",")).is("plain 1")

		harness.mock:reveal(model)
		harness.mock:step()

		expect(table.concat(harness.heard, ",")).is("plain 1,spawned 5")
		expect(rawequal(harness.models[1], model)).is(true)
		expect(#harness.failures).is(0)
	end)

	test("a message whose model is here goes ahead of one still waiting, which arrives once its model does", function ()
		local harness: Harness = setup()
		local hidden: any, visible: any = Instance.new("Model"), Instance.new("Model")

		harness.mock:hide(hidden)
		harness.server.World.Spawned.fire(harness.alice, hidden, 1)
		harness.server.World.Spawned.fire(harness.alice, visible, 2)
		exchange(harness.mock)

		expect(table.concat(harness.heard, ",")).is("spawned 2")

		harness.mock:reveal(hidden)
		harness.mock:step()

		expect(table.concat(harness.heard, ",")).is("spawned 2,spawned 1")
		expect(rawequal(harness.models[1], visible) and rawequal(harness.models[2], hidden)).is(true)
	end)

	test("messages naming one model arrive in the order fired, one fired after its reveal included", function ()
		local harness: Harness = setup()
		local model: any = Instance.new("Model")

		harness.mock:hide(model)
		harness.server.World.Spawned.fire(harness.alice, model, 1)
		harness.server.World.Spawned.fire(harness.alice, model, 2)
		exchange(harness.mock)

		expect(#harness.heard).is(0)

		harness.mock:reveal(model)
		harness.server.World.Spawned.fire(harness.alice, model, 3)
		exchange(harness.mock)

		expect(table.concat(harness.heard, ",")).is("spawned 1,spawned 2,spawned 3")
	end)

	test("a group with no leader arrives once, with every part, after the last of them is revealed", function ()
		local harness: Harness = setup()
		local first: any, second: any = Instance.new("Part"), Instance.new("Part")
		local groups: { string } = {}

		harness.client.World.Group.on(function (members: { any }, leader: any)
			local same: boolean = rawequal(members[1], first) and rawequal(members[2], second)
			table.insert(groups, `{#members} {same} {leader}`)
		end)

		harness.mock:hide(first)
		harness.mock:hide(second)
		harness.server.World.Group.fire(harness.alice, { first, second })
		exchange(harness.mock)

		harness.mock:reveal(first)
		harness.mock:step()

		expect(#groups).is(0)

		harness.mock:reveal(second)
		harness.mock:step()

		expect(table.concat(groups, ",")).is("2 true nil")
	end)

	test("a Brief whose part never arrives is dropped past its timeout as one resolve failure named for it", function ()
		local harness: Harness = setup()
		local part: any = Instance.new("Part")

		harness.mock:hide(part)
		harness.server.World.Brief.fire(harness.alice, part)
		exchange(harness.mock)
		outwait(harness.mock, BRIEF)

		-- Revealed too late, it brings nothing back
		harness.mock:reveal(part)
		harness.mock:step()

		local index: number? = harness.client.World.Brief.iter()()
		local report: Report = harness.failures[1]

		expect(index).is(nil)
		expect(`{#harness.failures} {report.player} {report.kind}`).is("1 nil resolve")
		expect(report.detail).is("World.Brief: instance 1 did not arrive within 0.001 seconds")
	end)

	test("a bot hears a message naming a model hidden from players in the step it is fired", function ()
		local harness: Harness = setup()
		local bot: Volt.Bot = harness.mock:addBot("Helper")
		local client: any = Generated.module("Client", CLIENT, harness.mock:connectBot(bot))
		local model: any = Instance.new("Model")
		local heard: { string } = {}

		client.World.Spawned.on(function (found: any, health: number)
			table.insert(heard, `{rawequal(found, model)} {health}`)
		end)

		harness.mock:hide(model)
		harness.server.World.Spawned.fire(bot, model, 5)
		harness.mock:step()

		expect(table.concat(heard, ",")).is("true 5")
	end)

	test("the server gives one model the same id in every message and another model its own", function ()
		local fired: { Fired } = {}
		local harness: Harness = setup(false, fired)
		local first: any, second: any = Instance.new("Model"), Instance.new("Model")

		harness.server.World.Spawned.fire(harness.alice, first, 1)
		harness.server.World.Spawned.fire(harness.alice, first, 2)
		harness.server.World.Spawned.fire(harness.alice, second, 3)
		harness.mock:step()

		local packet: buffer = fired[#fired].packet
		local ids: { number } = {}

		for offset: number = 0, buffer.len(packet) - 1, SPAWNED do
			table.insert(ids, buffer.readu32(packet, offset + 1))
		end

		expect(table.concat(ids, " ")).is("1 1 2")
	end)

	test("the server refuses an instance of another class, or none, at the fire and sends nothing of it", function ()
		local harness: Harness = setup()
		local World: any = harness.server.World
		local alice: any = harness.alice
		local part: any, model: any = Instance.new("Part"), Instance.new("Model")
		local raised: { string } = {}

		-- Each refusal as the rendered server module writes it, and a fire that raises it
		local refusals: { { any } } = {
			{
				"World.Spawned.model: expected AwaitedInstance(Model)",
				function ()
					World.Spawned.fire(alice, part, 1)
				end,
			},
			{
				"World.Spawned.model: expected AwaitedInstance(Model)",
				function ()
					World.Spawned.fireAll(nil, 1)
				end,
			},
			{
				"World.Brief: expected AwaitedInstance(BasePart)",
				function ()
					World.Brief.fire(alice, model)
				end,
			},
			{
				"World.Group.members[]: expected AwaitedInstance(BasePart)",
				function ()
					World.Group.fire(alice, { part, model })
				end,
			},
			{
				"World.Group.leader: expected AwaitedInstance",
				function ()
					World.Group.fire(alice, {}, "leader")
				end,
			},
			{
				"Tracked.part: expected AwaitedInstance(BasePart)",
				function ()
					World.Track.fire(alice, { part = part, at = Vector3.zero }, { part = model, at = Vector3.zero })
				end,
			},
		}

		local expected: { string } = {}

		for _, refusal: { any } in refusals do
			local ok: boolean, message: any = pcall(refusal[2])

			table.insert(expected, refusal[1])
			table.insert(raised, ok and "sent" or tostring(message))
		end

		World.Plain.fire(alice, 1)
		exchange(harness.mock)

		expect(table.concat(raised, "\n")).is(table.concat(expected, "\n"))
		expect(table.concat(harness.heard, ",")).is("plain 1")
		expect(#harness.failures).is(0)
	end)

	test("an unchecked server still refuses a nil model at the fire, and leaves nothing of it behind", function ()
		local harness: Harness = setup(true)
		local ok: boolean, message: any = pcall(harness.server.World.Spawned.fire, harness.alice, nil, 1)

		harness.server.World.Plain.fire(harness.alice, 1)
		exchange(harness.mock)

		expect(ok).is(false)
		expect(tostring(message)).is("World.Spawned.model: expected AwaitedInstance(Model)")
		expect(table.concat(harness.heard, ",")).is("plain 1")
		expect(#harness.failures).is(0)
	end)
end)
