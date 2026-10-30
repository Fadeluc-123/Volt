--[[
    Proves the baselines of @delta events over the mock, with a writer and
    a reader written by hand as generated ones would be: a mask per
    distinct baseline, one copy every recipient keeps, a drop that makes
    the next fire whole, and the client's merge filling and freezing
--]]

--!strict
local task = require("@lune/task")

local Baselines = require("./Baselines")
local Suite = require("./Suite")
local hex = require("./Hex")
local packet = require("./Packet")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Client = Baselines.Client
type Harness = Baselines.Harness
type Mock = Volt.Mock
type Report = Baselines.Report
type Runtime = Volt.Runtime
type Transport = Volt.Transport
type Vitals = Baselines.Vitals

type Write = (mask: number, value: any) -> ()

local VITALS: number = Baselines.vitals

local client = Baselines.client
local lines = Baselines.lines
local round = Baselines.round
local setup = Baselines.setup
local sorted = Baselines.sorted
local vitals = Baselines.make

describe("Delta", function ()
	test("recipients sharing a baseline are compared and written once, patched while the rest go whole", function ()
		local harness: Harness = setup({ "Alice", "Bob", "Carol" })
		local server: Runtime, write: Write = harness.server, harness.write
		local alice: any, bob: any, carol: any = table.unpack(harness.players)

		server:delta(VITALS, nil, { alice, bob }, nil, write, vitals(100, 50, 1))
		server:delta(VITALS, nil, nil, nil, write, vitals(90, 50, 1))
		server:delta(VITALS, nil, nil, carol, write, vitals(90, 40, 1))
		round(harness)

		expect(harness.masks[1]).is(7)
		expect(sorted(harness.masks)).is("1,2,7,7")
		expect(lines(harness.clients[alice])).is("100 50 1,90 50 1,90 40 1")
		expect(lines(harness.clients[bob])).is("100 50 1,90 50 1,90 40 1")
		expect(lines(harness.clients[carol])).is("90 50 1")
		expect(`{server:stats(alice).bytesOut} {server:stats(carol).bytesOut}`).is("11 5")
	end)

	test("every recipient keeps one copy of the value, its own, so an edit in place is sent", function ()
		local harness: Harness = setup({ "Alice", "Bob" })
		local alice: any, bob: any = table.unpack(harness.players)
		local players: any = (harness.server :: any)._players
		local value: Vitals = vitals(100, 50, 1)

		harness.server:delta(VITALS, nil, { alice, bob }, nil, harness.write, value)

		local kept: any = players[alice].sent[VITALS]

		expect(rawequal(kept, players[bob].sent[VITALS])).is(true)
		expect(rawequal(kept, value) or rawequal(kept.gear, value.gear)).is(false)

		value.gear.level = 2
		harness.server:delta(VITALS, nil, { alice, bob }, nil, harness.write, value)
		round(harness)

		expect(table.concat(harness.masks, ",")).is("7,4")
		expect(lines(harness.clients[alice])).is("100 50 1,100 50 2")
	end)

	test("an unchanged value is written as the id and an empty mask, two bytes, and is still heard", function ()
		local harness: Harness = setup({ "Alice" })
		local alice: any = harness.players[1]

		harness.server:delta(VITALS, alice, nil, nil, harness.write, vitals(100, 50, 1))
		round(harness)

		local before: number = harness.server:stats(alice).bytesOut

		harness.server:delta(VITALS, alice, nil, nil, harness.write, vitals(100, 50, 1))
		round(harness)

		expect(harness.server:stats(alice).bytesOut - before).is(2)
		expect(table.concat(harness.masks, ",")).is("7,0")
		expect(lines(harness.clients[alice])).is("100 50 1,100 50 1")
	end)

	for _, broadcast: boolean in { false, true } do
		local variant: string = broadcast and "a broadcast" or "a fire"

		test(`a message past the cap is dropped before {variant} works out its mask, so it goes whole`, function ()
			local harness: Harness = setup({ "Alice" }, { maxOutgoing = 8 })
			local server: Runtime, write: Write = harness.server, harness.write
			local alice: any = harness.players[1]
			local player: any = not broadcast and alice or nil

			server:delta(VITALS, alice, nil, nil, write, vitals(100, 50, 1))
			round(harness)

			-- Four bytes of patch after five of the plain event take the frame past eight, where the next fire finds it
			Baselines.fill(harness, alice)
			server:delta(VITALS, alice, nil, nil, write, vitals(90, 50, 2))
			server:delta(VITALS, player, nil, nil, write, vitals(80, 50, 2))
			round(harness)

			expect(lines(harness.clients[alice])).is("100 50 1,ping")

			server:delta(VITALS, alice, nil, nil, write, vitals(70, 50, 2))
			round(harness)

			local failures: { Report } = harness.failures

			expect(table.concat(harness.masks, ",")).is("7,5,7,7")
			expect(lines(harness.clients[alice])).is("100 50 1,ping,70 50 2")
			expect(`{#failures} {failures[1].kind} {failures[1].kept} {failures[2].kept}`).is("2 outgoing false false")
		end)
	end

	for _, checked: boolean in { true, false } do
		local variant: string = checked and "refused" or "raised by an unchecked writer"

		test(`a write {variant} sets no baseline, so the next fire is masked against the last one written`, function ()
			local harness: Harness = setup({ "Alice" }, { writeValidation = checked })
			local server: Runtime, write: Write = harness.server, harness.write
			local alice: any = harness.players[1]
			local wrong: any = { health = "full", stamina = 40, gear = { level = 1 } }

			server:delta(VITALS, alice, nil, nil, write, vitals(100, 50, 1))

			local ok: boolean, raised: any = pcall(server.delta, server, VITALS, alice, nil, nil, write, wrong)

			server:delta(VITALS, alice, nil, nil, write, vitals(90, 50, 1))
			round(harness)

			expect(ok).is(false)
			expect(tostring(raised):sub(1, 7)).is(checked and "vitals." or "vitals:")
			expect(table.concat(harness.masks, ",")).is("7,1")
			expect(lines(harness.clients[alice])).is("100 50 1,90 50 1")
			expect(server:stats(alice).messagesOut).is(2)
		end)
	end

	test("the hook before the send hears the player, the list or nothing, and a veto writes nothing", function ()
		local harness: Harness = setup({ "Alice", "Bob" })
		local alice: any, bob: any = table.unpack(harness.players)
		local hooked: { string } = {}

		harness.server.beforeSend("vitals", function (target: any, value: Vitals): boolean
			table.insert(hooked, target == nil and "all" or target.Name or `{#target} listed`)
			return target ~= nil and value.health > 0
		end)

		harness.server:delta(VITALS, alice, nil, nil, harness.write, vitals(100, 50, 1))
		harness.server:delta(VITALS, nil, { alice, bob }, nil, harness.write, vitals(90, 50, 1))
		harness.server:delta(VITALS, nil, nil, nil, harness.write, vitals(80, 50, 1))
		round(harness)

		expect(table.concat(hooked, ",")).is("Alice,2 listed,all")
		expect(sorted(harness.masks)).is("1,7,7")
		expect(lines(harness.clients[bob])).is("90 50 1")
		expect(harness.server:stats(nil).rejected).is(1)
	end)

	test("a bot keeps baselines as a player does", function ()
		local harness: Harness = setup({})
		local bot: Volt.Bot = harness.mock:addBot("Helper")

		harness.server:delta(VITALS, nil, nil, nil, harness.write, vitals(100, 50, 1))
		harness.server:delta(VITALS, bot, nil, nil, harness.write, vitals(100, 40, 1))
		round(harness)

		expect(table.concat(harness.masks, ",")).is("7,2")
		expect(harness.server:stats(bot).bytesOut).is(8)
	end)

	test("a @delta event on a channel rides that channel's send", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local alice: any, side: Transport = mock:join("Alice")
		local received: { string } = {}
		local server: Runtime

		local function writeHealth(mask: number, value: any)
			local offset: number, out: buffer = server.streams[1].begin(3)

			buffer.writeu8(out, offset, VITALS)
			buffer.writeu8(out, offset + 1, mask)
			buffer.writeu8(out, offset + 2, value.health)
		end

		local row: { [string]: any } = {
			name = "vitals",
			kind = "event",
			reliable = true,
			stream = 1,
			fields = { "health" },
			minBytes = 2,
			maxBytes = 3,
		}

		server = Volt.start(Baselines.schema("server", Baselines.options, { [VITALS] = row }, { "Bulk" }), mock.server)

		side.receive(function (_, bytes: buffer)
			table.insert(received, hex(bytes))
		end)

		side.reliable(nil, packet({ 0, 0, 0, 0, 0, 0 }))
		mock:step()

		server:delta(VITALS, alice, nil, nil, writeHealth, { health = 100 })
		mock:step()
		mock:step()

		expect(table.concat(received, ",")).is("01 01 01 64")
	end)

	test("merge fills what the mask leaves out from the last value and hands the listener a frozen table", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local alice: any, transport: Transport = mock:join("Alice")
		local heard: { any } = client(transport).heard

		mock.server.reliable(alice, packet({ VITALS, 7, 100, 50, 1, VITALS, 1, 90 }))
		mock:step()

		local first: Vitals, second: Vitals = heard[1], heard[2]

		expect(`{second.health} {second.stamina} {second.gear.level}`).is("90 50 1")
		expect(rawequal(second.gear, first.gear)).is(true)
		expect(table.isfrozen(first) and table.isfrozen(second)).is(true)
	end)

	test("a message leaving a field out before any value is a decode failure named for the event", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local alice: any, transport: Transport = mock:join("Alice")
		local listener: Client = client(transport)

		mock.server.reliable(alice, packet({ VITALS, 1, 90 }))
		mock.server.reliable(alice, packet({ VITALS, 7, 100, 50, 1 }))
		mock:step()

		local report: Report = listener.failures[1]
		local line: string = `{#listener.failures} {report.player} {report.kind} {report.detail}`

		expect(line).is("1 nil decode vitals: no baseline")
		expect(lines(listener)).is("100 50 1")
	end)
end)
