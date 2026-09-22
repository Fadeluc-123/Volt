--[[
    Proves the assembled modules: each side of the Events and Broadcasts
    schemas and their types render as their golden files, and over the
    mock the generated API carries every call mode, every fire variant, a
    two-way event, an instance in the side array and unreliable fires
    batched to the budget; casing renames the members, a name the API
    owns is refused
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Environment = require("./Environment")
local Generated = require("./Generated")
local golden = require("./Expected")
local Volt = require("@volt")
local Contract = require("@volt/Compiler/Config/Contract")
local Targets = require("@volt/Compiler/Targets")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock

-- A server and two clients over one mock, each running the generated module of its side
type Harness = {
	mock: Mock,
	server: any, -- The server module
	players: { alice: any, bob: any },
	clients: { alice: any, bob: any }, -- Each player's client module
}

-- The three modules of one schema, with the schema text they came from
type Modules = { schema: string, client: string, server: string, types: string }

local Instance = Environment.Instance

local SCHEMAS: { string } = { "Events", "Broadcasts" } -- The client-fired forms and the two-way event, then the server-fired forms
local SIDES: { string } = { "Client", "Server", "Types" }
local SPRAYS: number = 400 -- Unreliable fires of three bytes in one frame, more than one packet of the budget holds
local BUDGET: number = 900 -- The schema's unreliable budget, which every packet must fit

local MODULES: { [string]: Modules } = {}

for _, name: string in SCHEMAS do
	local schema: string = fs.readFile(`tests/Schemas/{name}.volt`)
	local client: string, server: string, types: string = Generated.modules(name, schema)

	MODULES[name] = {
		schema = schema,
		client = client,
		server = server,
		types = types,
	}
end

local function setup(name: string): Harness
	local modules: Modules = MODULES[name]
	local mock: Mock = Volt.mock(task.spawn)
	local alice, aliceTransport = mock:join("Alice")
	local bob, bobTransport = mock:join("Bob")

	return {
		mock = mock,
		server = Generated.module("Server", modules.server, mock.server),
		players = { alice = alice, bob = bob },
		clients = {
			alice = Generated.module("Client", modules.client, aliceTransport),
			bob = Generated.module("Client", modules.client, bobTransport),
		},
	}
end

-- One step flushes what was fired and the next delivers it
local function exchange(mock: Mock)
	mock:step()
	mock:step()
end

describe("Targets", function ()
	for _, name: string in SCHEMAS do
		for _, side: string in SIDES do
			test(`renders the {name} {side:lower()} module as its golden file`, function ()
				local text: string = (MODULES[name] :: any)[side:lower()]
				expect(golden(`tests/Golden/{name}`, side, text)).is(text)
			end)
		end
	end

	test("stamps the schema table with the runtime's version", function ()
		expect(Contract.version).is(Volt.version)
		expect(MODULES.Events.server:find(`version = "{Volt.version}"`, 1, true) ~= nil).is(true)
	end)

	test("refuses a top-level name the API owns, in the schema's casing", function ()
		local text: string =
			`option casing = pascal\n{MODULES.Events.schema}\nevent OnFailure \{ from: Client, type: Reliable, call: SingleSync }`
		local file, hash, diagnostics = Generated.compile("Bad", text)

		Targets.modules(file, diagnostics, hash)

		expect(diagnostics.errors).is(1)
		expect(diagnostics:render():find('error V4001: "OnFailure" is a member of the generated API', 1, true) ~= nil).is(
			true
		)
	end)

	test("renames every member in the casing asked for, the handle types with them", function ()
		local schema: string = MODULES.Broadcasts.schema
		local client: string, pascal: string, pascalTypes: string =
			Generated.modules("Broadcasts", `option casing = pascal\n{schema}`)
		local snake: string = select(2, Generated.modules("Broadcasts", `option casing = snake\n{schema}`))
		local both: string = `{client}{pascal}` -- The server fires, the client hears

		for _, name: string in
			{ "Fire", "FireAll", "FireList", "FireExcept", "FireSet", "On", "Iter", "OnFailure", "Stats" }
		do
			expect(both:find(`{name} = function`, 1, true) ~= nil).is(true)
		end

		for _, name: string in { "fire_all", "fire_list", "fire_except", "fire_set", "on_failure" } do
			expect(snake:find(`{name} = function`, 1, true) ~= nil).is(true)
		end

		expect(pascal:find("BeforeSend = runtime.beforeSend", 1, true) ~= nil).is(true)
		expect(pascal:find("net.Events = table.freeze", 1, true) ~= nil).is(true)
		expect(pascalTypes:find("\tFireAll: (A...) -> (),", 1, true) ~= nil).is(true)
	end)

	describe("over the mock", function ()
		test("a client fire reaches a sync listener with the player first", function ()
			local harness: Harness = setup("Events")
			local heard: { string } = {}

			harness.server.Input.on(function (player: any, dir: number, jump: boolean)
				table.insert(heard, `{player.Name} {dir} {jump}`)
			end)

			harness.clients.alice.Input.fire(3, true)
			harness.clients.bob.Input.fire(5, false)
			exchange(harness.mock)

			expect(table.concat(heard, ",")).is("Alice 3 true,Bob 5 false")
		end)

		test("an async listener hears a single value on a thread of its own", function ()
			local harness: Harness = setup("Events")
			local heard: string? = nil
			local thread: thread? = nil

			harness.server.Chat.on(function (_, text: string)
				heard = text
				thread = coroutine.running()
			end)

			harness.clients.alice.Chat.fire("hello")
			exchange(harness.mock)

			expect(heard).is("hello")
			expect(thread ~= nil and thread ~= coroutine.running()).is(true)
		end)

		test("many sync listeners hear an empty event in connection order", function ()
			local harness: Harness = setup("Events")
			local heard: { string } = {}

			harness.server.Ready.on(function (player: any)
				table.insert(heard, `first {player.Name}`)
			end)
			harness.server.Ready.on(function (player: any)
				table.insert(heard, `second {player.Name}`)
			end)

			harness.clients.bob.Ready.fire()
			exchange(harness.mock)

			expect(table.concat(heard, ",")).is("first Bob,second Bob")
		end)

		test("an instance crosses in the side array", function ()
			local harness: Harness = setup("Events")
			local folder = Instance.new("Folder")
			local heard: any = nil

			harness.server.Grab.on(function (_, instance: any)
				heard = instance
			end)

			harness.clients.alice.Grab.fire(folder)
			exchange(harness.mock)

			expect(heard == folder).is(true)
		end)

		test("a polled event drains through iter with the index and the player, and has no on", function ()
			local harness: Harness = setup("Events")
			local rows: { string } = {}

			harness.clients.alice.Ping.fire(7)
			harness.clients.bob.Ping.fire(9)
			exchange(harness.mock)

			for index: number, player: any, value: number in harness.server.Ping.iter() do
				table.insert(rows, `{index} {player.Name} {value}`)
			end

			expect(table.concat(rows, ",")).is("1 Alice 7,2 Bob 9")
			expect(harness.server.Ping.on).is(nil)
		end)

		test("fire reaches one player and each broadcast the players it names", function ()
			local harness: Harness = setup("Broadcasts")
			local players = harness.players
			local heard: { [string]: { number } } = { Alice = {}, Bob = {} }

			harness.clients.alice.Damage.on(function (hit: { [string]: number })
				table.insert(heard.Alice, hit.amount)
			end)
			harness.clients.bob.Damage.on(function (hit: { [string]: number })
				table.insert(heard.Bob, hit.amount)
			end)

			harness.server.Damage.fire(players.alice, { target = 1, amount = 1 })
			harness.server.Damage.fireAll({ target = 1, amount = 2 })
			harness.server.Damage.fireList({ players.bob }, { target = 1, amount = 3 })
			harness.server.Damage.fireExcept(players.alice, { target = 1, amount = 4 })
			harness.server.Damage.fireSet({ [players.alice] = true }, { target = 1, amount = 5 })
			exchange(harness.mock)

			expect(table.concat(heard.Alice, ",")).is("1,2,5")
			expect(table.concat(heard.Bob, ",")).is("2,3,4")
		end)

		test("a namespaced empty event polls on the client without a player", function ()
			local harness: Harness = setup("Broadcasts")
			local rows: { string } = {}

			harness.server.Match.Start.fireAll()
			exchange(harness.mock)

			for index: number, extra: any in harness.clients.alice.Match.Start.iter() do
				table.insert(rows, `{index} {extra}`)
			end

			expect(table.concat(rows, ",")).is("1 nil")
		end)

		test("a fire at a player who left is a counted no-op", function ()
			local harness: Harness = setup("Broadcasts")
			local departed: number = 0

			harness.server.onFailure(function (_, kind: string)
				if kind == "departed" then
					departed += 1
				end
			end)

			harness.mock:leave(harness.players.bob)
			harness.server.Damage.fire(harness.players.bob, { target = 1, amount = 1 })
			exchange(harness.mock)

			expect(departed).is(1)
		end)

		test("unreliable fires batch into packets that fit the budget, every message arriving", function ()
			local mock: Mock = Volt.mock(task.spawn)
			local sizes: { number } = {}
			local send = mock.server.unreliable

			-- Counted before the server module starts, since the runtime takes the transport's functions at start
			mock.server.unreliable = function (player: any, packet: buffer, side: { any }?)
				table.insert(sizes, buffer.len(packet))
				send(player, packet, side)
			end

			local alice, transport = mock:join("Alice")
			local serverNet = Generated.module("Server", MODULES.Broadcasts.server, mock.server)
			local aliceNet = Generated.module("Client", MODULES.Broadcasts.client, transport)
			local heard: number = 0

			aliceNet.Spray.on(function ()
				heard += 1
			end)

			for index: number = 1, SPRAYS do
				serverNet.Spray.fire(alice, index % 256, 0)
			end

			exchange(mock)

			expect(heard).is(SPRAYS)
			expect(#sizes > 1).is(true)

			for _, size: number in sizes do
				expect(size <= BUDGET).is(true)
			end
		end)

		test("a two-way event carries both ways", function ()
			local harness: Harness = setup("Events")
			local serverHeard: string? = nil
			local clientHeard: number? = nil

			harness.server.Sync.on(function (player: any, value: number)
				serverHeard = `{player.Name} {value}`
			end)
			harness.clients.alice.Sync.on(function (value: number)
				clientHeard = value
			end)

			harness.clients.alice.Sync.fire(1)
			harness.server.Sync.fire(harness.players.alice, 2)
			exchange(harness.mock)

			expect(serverHeard).is("Alice 1")
			expect(clientHeard).is(2)
		end)

		test("flush sends what was fired before the Heartbeat would", function ()
			local harness: Harness = setup("Events")
			local heard: number? = nil

			harness.server.Sync.on(function (_, value: number)
				heard = value
			end)

			harness.clients.alice.Sync.fire(4)
			harness.clients.alice.flush()
			harness.mock:step()

			expect(heard).is(4)
		end)
	end)
end)
