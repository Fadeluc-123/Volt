--[[
    Proves replication end to end over the generated modules on the mock:
    a joiner hears no plain event fired before it joined and is sent the
    whole dictionary first, held messages included, and each recipient of
    a @delta event, a bot or one on a channel among them, keeps a baseline
    of its own through every fire variant, a drop and a fire from onJoin
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
type Runtime = Volt.Runtime

type Value = { [string]: any }

-- A server over one mock running its side of a schema, the client module its players start, and what it reported
type Harness = { mock: Mock, server: any, client: string, failures: { string } }

local SCHEMAS: string = "tests/Schemas"
local ENTRIES: number = Config.dictionaryEntries
local CAP: number = 16 -- A frame in Capped: a whole vitals fits, while a zone and two patches of one cross it

local DELTAS: string = fs.readFile(`{SCHEMAS}/Deltas.volt`)

-- A @delta event on a channel, which a baseline may ride though a dictionary string may not
local OUTPUTS: string = `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"\n`
local KEYS: string = "from: Server, type: Reliable, call: ManySync, channel: Bulk"
local CHANNELED: string = `{OUTPUTS}channel Bulk\n@delta event status \{ {KEYS}, data: struct \{ hp: u8, mp: u8 } }`

-- Each schema's text, by the name the tests serve it under
local TEXTS: { [string]: string } = {
	Deltas = DELTAS,
	Capped = `option maxOutgoing = {CAP}\n{DELTAS}`,
	Dictionary = fs.readFile(`{SCHEMAS}/Dictionary.volt`),
	Broadcasts = fs.readFile(`{SCHEMAS}/Broadcasts.volt`),
	Channeled = CHANNELED,
}

local MODULES: { [string]: { client: string, server: string } } = {}

for name: string, text: string in TEXTS do
	local client: string, server: string = Generated.modules(name, text)

	MODULES[name] = { client = client, server = server }
end

-- A server over one mock running its side of a schema's modules, keeping every failure it reports
local function serve(name: string): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local server: any = Generated.module("Server", MODULES[name].server, mock.server)
	local failures: { string } = {}

	server.onFailure(function (_, kind: string, detail: string)
		table.insert(failures, `{kind} {detail}`)
	end)

	return { mock = mock, server = server, client = MODULES[name].client, failures = failures }
end

-- A player joins and starts the client module at once, which sends its handshake in its first frame
local function join(harness: Harness, name: string): (any, any, Runtime)
	local player: any, transport: Volt.Transport = harness.mock:join(name)
	local client: any, runtime: Runtime = Generated.module("Client", harness.client, transport)

	return player, client, runtime
end

local function steps(mock: Mock, count: number)
	for _ = 1, count do
		mock:step()
	end
end

-- What a fire costs each player given once it has gone out, a step before their clients hear it
local function costs(harness: Harness, players: { any }, fire: (...any) -> (), ...: any): string
	local before: { number } = {}
	local spent: { number } = {}

	for index: number, player: any in players do
		before[index] = harness.server.stats(player).bytesOut
	end

	fire(...)
	steps(harness.mock, 2)

	for index: number, player: any in players do
		spent[index] = harness.server.stats(player).bytesOut - before[index]
	end

	return table.concat(spent, " ")
end

-- A vitals value of its own, its nested struct included, so an edit in place is the test's alone
local function vitals(): Value
	return { health = 100, stamina = 50, title = "Scout", held = 7, gear = { shield = true, boots = false } }
end

-- Every vitals a client hears, a line each with its nested struct, marked if the listener could write into it
local function heard(client: any): { string }
	local lines: { string } = {}

	client.vitals.on(function (value: Value)
		local gear: Value = value.gear
		local line: string = `{value.health} {value.stamina} {value.title} {value.held} {gear.shield} {gear.boots}`

		table.insert(lines, table.isfrozen(value) and line or `{line} unfrozen`)
	end)

	return lines
end

-- Every picked a client hears, a line each
local function picks(client: any): { string }
	local lines: { string } = {}

	client.picked.on(function (item: string, title: string)
		table.insert(lines, `{item} {title}`)
	end)

	return lines
end

describe("Replication", function ()
	test("a joiner hears nothing of a plain reliable event fired before it joined", function ()
		local harness: Harness = serve("Broadcasts")
		local _, alice: any = join(harness, "Alice")
		local shaken: { string } = {}
		local hits: { string } = {}

		harness.server.onHandshake(function (player: any)
			table.insert(shaken, player.Name)
		end)
		alice.Damage.on(function (hit: Value)
			table.insert(hits, `Alice {hit.target} {hit.amount}`)
		end)

		harness.server.Damage.fireAll({ target = 1, amount = 2 })
		steps(harness.mock, 3)

		local bob: any, client: any = join(harness, "Bob")

		client.Damage.on(function (hit: Value)
			table.insert(hits, `Bob {hit.target} {hit.amount}`)
		end)
		steps(harness.mock, 5)

		expect(table.concat(shaken, ",")).is("Alice,Bob")
		expect(table.concat(hits, ",")).is("Alice 1 2")
		expect(harness.server.stats(bob).messagesOut).is(0)
	end)

	test("a dictionary string fired at a player before their client starts decodes once it handshakes", function ()
		local harness: Harness = serve("Dictionary")
		local alice: any, transport: Volt.Transport = harness.mock:join("Alice")

		harness.server.picked.fire(alice, "Sword", "Scout")
		steps(harness.mock, 3)

		local lines: { string } = picks((Generated.module("Client", harness.client, transport)))

		steps(harness.mock, 3)

		expect(table.concat(lines, ",")).is("Sword Scout")
		expect(#harness.failures).is(0)
	end)

	test("a joiner is sent the whole dictionary first, and strings a player holds cost their ids alone", function ()
		local harness: Harness = serve("Dictionary")
		local alice: any, first: any = join(harness, "Alice")
		local alices: { string } = picks(first)

		harness.server.picked.fire(alice, "Sword", "Scout")
		harness.server.picked.fire(alice, "Bow", "Hunter")
		steps(harness.mock, 3)

		-- The id and two ids, with no entry to send ahead of them
		local known: string = costs(harness, { alice }, harness.server.picked.fire, alice, "Sword", "Hunter")
		local bob: any, second: any, runtime: Runtime = join(harness, "Bob")
		local bobs: { string } = picks(second)

		harness.server.picked.fire(bob, "Bow", "Scout")
		steps(harness.mock, 3)

		expect(known).is("5")
		expect(table.concat(alices, ",")).is("Sword Scout,Bow Hunter,Sword Hunter")
		expect(table.concat(bobs, ",")).is("Bow Scout")
		expect(table.concat(runtime.dictionary, ",")).is("Sword,Scout,Bow,Hunter")
	end)

	test("the string past the dictionary's last entry is refused", function ()
		local harness: Harness = serve("Dictionary")
		local alice: any = harness.mock:join("Alice")

		-- Each fire adds two strings, so these fill every entry
		for index: number = 1, ENTRIES / 2 do
			harness.server.picked.fire(alice, `item {index}`, `title {index}`)
		end

		local ok: boolean, message: any = pcall(harness.server.picked.fire, alice, "Shield", "Scout")

		expect(`{ok} {message}`).is("false picked.item: dictionary full")
	end)

	test("a @delta fire sends the fields that changed, deeply, and every value arrives whole and frozen", function ()
		local harness: Harness = serve("Deltas")
		local alice: any, client: any = join(harness, "Alice")
		local lines: { string } = heard(client)
		local fire: (...any) -> () = harness.server.vitals.fire
		local value: Value = vitals()
		local spent: { string } = {}

		fire(alice, value)
		steps(harness.mock, 3)
		table.insert(spent, `{harness.server.stats(alice).bytesOut}`)

		value.health = 90
		table.insert(spent, costs(harness, { alice }, fire, alice, value))
		table.insert(spent, costs(harness, { alice }, fire, alice, value))
		value.gear.boots = true
		table.insert(spent, costs(harness, { alice }, fire, alice, value))
		value.held = nil
		table.insert(spent, costs(harness, { alice }, fire, alice, value))

		-- Whole, then the id and the mask with one byte each: health, nothing, the nested struct and the optional's flag
		expect(table.concat(spent, ",")).is("14,3,2,3,3")
		expect(table.concat(lines, ",")).is(table.concat({
			"100 50 Scout 7 true false",
			"90 50 Scout 7 true false",
			"90 50 Scout 7 true false",
			"90 50 Scout 7 true true",
			"90 50 Scout nil true true",
		}, ","))
	end)

	test("each recipient keeps a baseline of its own through every fire variant", function ()
		local harness: Harness = serve("Deltas")
		local alice: any, first: any = join(harness, "Alice")
		local bob: any, second: any = join(harness, "Bob")
		local alices: { string }, bobs: { string } = heard(first), heard(second)
		local both: { any } = { alice, bob }
		local event: any = harness.server.vitals
		local value: Value = vitals()
		local spent: { string } = {}

		event.fire(alice, value)
		steps(harness.mock, 3)

		value.health = 90
		table.insert(spent, costs(harness, both, event.fireAll, value))
		value.stamina = 40
		table.insert(spent, costs(harness, both, event.fireList, both, value))
		value.title = "Ranger"
		table.insert(spent, costs(harness, both, event.fireSet, { [bob] = true }, value))
		table.insert(spent, costs(harness, both, event.fireExcept, bob, value))
		table.insert(spent, costs(harness, both, event.fireAll, value))

		-- Alice patched where Bob goes whole, both patched, each patched alone on the title, then both unchanged
		expect(table.concat(spent, ",")).is("3 14,3 3,0 9,9 0,2 2")
		expect(table.concat(alices, ",")).is(table.concat({
			"100 50 Scout 7 true false",
			"90 50 Scout 7 true false",
			"90 40 Scout 7 true false",
			"90 40 Ranger 7 true false",
			"90 40 Ranger 7 true false",
		}, ","))
		expect(table.concat(bobs, ",")).is(table.concat({
			"90 50 Scout 7 true false",
			"90 40 Scout 7 true false",
			"90 40 Ranger 7 true false",
			"90 40 Ranger 7 true false",
		}, ","))
	end)

	test("a @delta message dropped past the cap makes the next fire whole, with the value right", function ()
		local harness: Harness = serve("Capped")
		local alice: any, client: any = join(harness, "Alice")
		local lines: { string } = heard(client)
		local event: any = harness.server.vitals
		local value: Value = vitals()

		event.fire(alice, value)
		steps(harness.mock, 3)

		-- A zone and the title's patch fit the frame, and the health's patch after them crosses the cap and is dropped
		value.title = "Ranger"
		harness.server.zone.fire(alice, { id = 1, safe = true })
		event.fire(alice, value)
		value.health = 80

		local dropped: string = costs(harness, { alice }, event.fire, alice, value)

		-- The baseline the dropped patch set went with it, so the same value goes again, whole
		local whole: string = costs(harness, { alice }, event.fire, alice, value)

		expect(`{dropped},{whole}`).is("14,15")
		expect(`{#harness.failures} {harness.failures[1]:match("^%a+")}`).is("1 outgoing")
		expect(table.concat(lines, ",")).is(
			"100 50 Scout 7 true false,100 50 Ranger 7 true false,80 50 Ranger 7 true false"
		)
	end)

	test("a @delta fire from onJoin before the handshake arrives whole after it, and the next is a patch", function ()
		local harness: Harness = serve("Deltas")

		harness.server.onJoin(function (player: any)
			harness.server.vitals.fire(player, vitals())
		end)

		local alice: any, client: any = join(harness, "Alice")
		local lines: { string } = heard(client)
		local value: Value = vitals()

		value.health = 90
		steps(harness.mock, 3)

		local whole: number = harness.server.stats(alice).bytesOut
		local patch: string = costs(harness, { alice }, harness.server.vitals.fire, alice, value)

		expect(`{whole} {patch}`).is("14 3")
		expect(table.concat(lines, ",")).is("100 50 Scout 7 true false,90 50 Scout 7 true false")
	end)

	test("a bot is sent @delta patches and dictionary entries as a player is", function ()
		local deltas: Harness = serve("Deltas")
		local dictionary: Harness = serve("Dictionary")
		local bot: Volt.Bot = deltas.mock:addBot("Helper")
		local reader: Volt.Bot = dictionary.mock:addBot("Reader")
		local lines: { string } = heard((Generated.module("Client", deltas.client, deltas.mock:connectBot(bot))))
		local client: any, runtime: Runtime =
			Generated.module("Client", dictionary.client, dictionary.mock:connectBot(reader))
		local picked: { string } = picks(client)
		local value: Value = vitals()

		deltas.server.vitals.fireAll(value)
		steps(deltas.mock, 2)
		value.health = 90

		local patch: string = costs(deltas, { bot }, deltas.server.vitals.fire, bot, value)

		dictionary.server.picked.fire(reader, "Sword", "Scout")
		steps(dictionary.mock, 2)

		expect(patch).is("3")
		expect(table.concat(lines, ",")).is("100 50 Scout 7 true false,90 50 Scout 7 true false")
		expect(`{table.concat(picked, ",")} {table.concat(runtime.dictionary, ",")}`).is("Sword Scout Sword,Scout")
	end)

	test("a @delta event on a channel keeps its baselines as one on the default stream does", function ()
		local harness: Harness = serve("Channeled")
		local alice: any, client: any = join(harness, "Alice")
		local lines: { string } = {}

		client.status.on(function (value: Value)
			table.insert(lines, `{value.hp} {value.mp}`)
		end)

		harness.server.status.fire(alice, { hp = 10, mp = 5 })
		steps(harness.mock, 3)

		-- The channel's byte opens the packet, then the id, the mask and hp's one byte
		local patch: string = costs(harness, { alice }, harness.server.status.fire, alice, { hp = 9, mp = 5 })

		expect(patch).is("4")
		expect(table.concat(lines, ",")).is("10 5,9 5")
		expect(#harness.failures).is(0)
	end)
end)
