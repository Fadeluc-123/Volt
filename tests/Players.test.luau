--[[
    Proves the player lifecycle over the mock and the generated modules:
    a fire naming a joiner before Volt's own join reaches them, one after
    their leave recreates nothing, what is fired before a handshake waits
    for it, a refused player hears nothing, bots added or started before
    a runtime or after it, the callbacks with live stats and the byte count
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local handshake = require("./Handshake")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Bot = Volt.Bot
type Mock = Volt.Mock
type Runtime = Volt.Runtime

type Hit = { target: number, amount: number }

local SCHEMAS: { string } = { "Broadcasts", "Events" } -- A reliable and an unreliable event the server fires, then the client's
local WRONG_HASH: number = 0xBAD -- A hash neither schema has
local DAMAGE_BYTES: number = 4 -- One Damage message: its id, a u16 and a u8

-- Every kind of failure, which the default handler takes for a bot without kicking it or raising
local KINDS: { string } =
	{ "packet", "rate", "handshake", "decode", "listener", "handler", "outgoing", "queue", "departed" }

local MODULES: { [string]: { client: string, server: string } } = {}

for _, name: string in SCHEMAS do
	local client: string, server: string = Generated.modules(name, fs.readFile(`tests/Schemas/{name}.volt`))
	MODULES[name] = { client = client, server = server }
end

-- A server module over a mock with every failure it reports kept, then the runtime it started
local function serve(name: string, mock: Mock): (any, { string }, Runtime)
	local server: any, runtime: Runtime = Generated.module("Server", MODULES[name].server, mock.server)
	local failures: { string } = {}

	server.onFailure(function (_, kind: string, detail: string)
		table.insert(failures, `{kind}: {detail}`)
	end)

	return server, failures, runtime
end

-- A server fire before a client's handshake waits for it: one step flushes the handshake, one reads it, one delivers
local function held(mock: Mock)
	mock:step()
	mock:step()
	mock:step()
end

describe("Players", function ()
	test(
		"a fire, a list fire or a set fire from a join callback that ran before Volt's arrives once, after the handshake",
		function ()
			local mock: Mock = Volt.mock(task.spawn)
			local hit: Hit = { target = 1, amount = 7 }
			local heard: { string } = {}
			local server: any, failures: { string }

			-- Registered before the module starts, so it hears each join before Volt's own callback does
			assert(mock.server.playerAdded, "the server side has players")(function (player: any)
				if player.Name == "Alice" then
					server.Damage.fire(player, hit)
				elseif player.Name == "Bob" then
					server.Damage.fireList({ player }, hit)
				else
					server.Damage.fireSet({ [player] = true }, hit)
				end
			end)

			server, failures = serve("Broadcasts", mock)

			for _, name: string in { "Alice", "Bob", "Carol" } do
				local _, transport = mock:join(name)
				local client: any = Generated.module("Client", MODULES.Broadcasts.client, transport)

				client.Damage.on(function (got: Hit)
					table.insert(heard, `{name} {got.amount}`)
				end)
			end

			held(mock)
			held(mock)
			table.sort(heard)

			expect(table.concat(heard, ",")).is("Alice 7,Bob 7,Carol 7")
			expect(#failures).is(0)
		end
	)

	test("a fire from a leave callback that runs after Volt's, or at someone never here, is departed", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local alice = mock:join("Alice")
		local server: any, failures: { string }, runtime: Runtime = serve("Broadcasts", mock)
		local kept: any = runtime :: any -- What the runtime keeps per player, which its type does not show
		local hit: Hit = { target = 1, amount = 1 }

		assert(mock.server.playerRemoving, "the server side has players")(function (player: any)
			server.Damage.fire(player, hit)
		end)

		mock:leave(alice)
		server.Damage.fire({ Name = "Ghost" }, hit)

		expect(table.concat(failures, ",")).is(
			"departed: fired at a player who has left,departed: fired at a player who has left"
		)
		expect(kept._players[alice] == nil and kept.reliable._states[alice] == nil).is(true)
		expect(kept.unreliable._states[alice]).is(nil)
	end)

	test(
		"reliable fires before a client starts arrive in order after its handshake, and unreliable ones never",
		function ()
			local mock: Mock = Volt.mock(task.spawn)
			local alice, transport = mock:join("Alice")
			local server: any = serve("Broadcasts", mock)
			local damage: { number }, sprays: number = {}, 0

			for amount: number = 1, 3 do
				server.Damage.fire(alice, { target = 1, amount = amount })
				server.Spray.fire(alice, amount, 0)
				mock:step()
			end

			local client: any = Generated.module("Client", MODULES.Broadcasts.client, transport)

			client.Damage.on(function (hit: Hit)
				table.insert(damage, hit.amount)
			end)
			client.Spray.on(function ()
				sprays += 1
			end)

			held(mock)

			expect(`{table.concat(damage, ",")} {sprays}`).is("1,2,3 0")
		end
	)

	test("a refused handshake leaves that player hearing nothing while another still gets every broadcast", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local alice, aliceSide = mock:join("Alice")
		local bob, bobSide = mock:join("Bob")
		local server: any, failures: { string }, runtime: Runtime = serve("Broadcasts", mock)
		local client: any = Generated.module("Client", MODULES.Broadcasts.client, bobSide)
		local packets: number = 0
		local heard: { number } = {}

		aliceSide.receive(function ()
			packets += 1
		end)
		client.Damage.on(function (hit: Hit)
			table.insert(heard, hit.amount)
		end)

		-- Both are written before either handshake is read: Alice's is held and then dropped, Bob's held and then sent
		aliceSide.reliable(nil, handshake(WRONG_HASH))
		server.Damage.fire(alice, { target = 1, amount = 1 })
		server.Damage.fire(bob, { target = 1, amount = 1 })
		mock:step()

		server.Damage.fire(alice, { target = 1, amount = 2 })
		server.Spray.fire(alice, 2, 0)
		server.Damage.fireAll({ target = 1, amount = 3 })
		held(mock)

		local stats: Volt.Stats = runtime:stats(alice)

		expect(`{packets} {table.concat(heard, ",")}`).is("0 1,3")
		expect(`{stats.failures.handshake} {stats.failures.departed} {stats.messagesOut}`).is("1 2 1")
		expect(select(2, runtime:traffic(alice))).is(0)
		expect(failures[2]).is("departed: fired at a player whose handshake failed")
	end)

	test(
		"a bot joins, is fired at, counts, sends through a client runtime of its own and hears back, then leaves",
		function ()
			local mock: Mock = Volt.mock(task.spawn)
			local server: any, failures: { string }, runtime: Runtime = serve("Events", mock)
			local seen: { string } = {}
			local heard: { number } = {}

			runtime:onLeave(function (player: any)
				table.insert(seen, `left {runtime:stats(player).messagesIn}`)
			end)
			server.Ready.on(function (player: any)
				table.insert(seen, `ready {runtime.isBot(player)}`)
				server.Sync.fire(player, 5)
			end)

			local bot: Bot = mock:addBot("Helper")
			local client: any = Generated.module("Client", MODULES.Events.client, mock:connectBot(bot))

			client.Sync.on(function (value: number)
				table.insert(heard, value)
			end)
			client.Ready.fire()

			-- The bot's frame hands its packet to the server in the same step, and the next frame hands it the answer
			mock:step()
			expect(table.concat(seen, ",")).is("ready true")

			mock:step()
			expect(table.concat(heard, ",")).is("5")
			expect(runtime:stats(bot).messagesIn).is(1)
			expect(`{#mock.players} {(bot :: any).Kick}`).is("0 nil")

			mock:removeBot(bot)

			expect(table.concat(seen, ",")).is("ready true,left 1")
			expect(runtime:stats(bot).messagesIn).is(0)
			expect(#failures).is(0)
		end
	)

	test("the default failure handler takes every kind for a bot without kicking it or raising", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local _, runtime: Runtime = Generated.module("Server", MODULES.Events.server, mock.server)
		local bot: Bot = mock:addBot("Helper")
		local default: Volt.Failure = runtime:onFailure(function () end)
		local raised: { string } = {}

		for _, kind: string in KINDS do
			if not pcall(default, bot, kind, "a detail") then
				table.insert(raised, kind)
			end
		end

		expect(#raised).is(0)
		expect(runtime:stats(bot).messagesIn).is(0)
	end)

	test(
		"onJoin replays everyone already set up, bots too, then each later join, and each disconnect is its own",
		function ()
			local mock: Mock = Volt.mock(task.spawn)
			local seen: { string } = {}

			mock:join("Alice")

			local _, _, runtime: Runtime = serve("Events", mock)

			mock:addBot("Helper")

			local first: () -> () = runtime:onJoin(function (player: any)
				table.insert(seen, `first {player.Name}`)
			end)
			runtime:onJoin(function (player: any)
				table.insert(seen, `second {player.Name}`)
			end)

			first()
			mock:join("Carol")
			table.sort(seen)

			expect(table.concat(seen, ",")).is("first Alice,first Helper,second Alice,second Carol,second Helper")
		end
	)

	test("onJoin hears a player or a bot once their stats are live, and onLeave before they go", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local _, _, runtime: Runtime = serve("Events", mock)
		local joined: { [any]: Volt.Stats } = {}
		local left: { string } = {}

		runtime:onJoin(function (player: any)
			joined[player] = runtime:stats(player)
		end)
		runtime:onLeave(function (player: any)
			table.insert(left, `{player.Name} {rawequal(runtime:stats(player), joined[player])}`)
		end)

		local alice: any = mock:join("Alice")
		local bot: Bot = mock:addBot("Helper")

		expect(rawequal(runtime:stats(alice), joined[alice]) and rawequal(runtime:stats(bot), joined[bot])).is(true)

		mock:leave(alice)
		mock:removeBot(bot)

		expect(table.concat(left, ",")).is("Alice true,Helper true")
		expect(rawequal(runtime:stats(alice), joined[alice]) or rawequal(runtime:stats(bot), joined[bot])).is(false)
	end)

	test("a bot added before a runtime starts is set up by it, fired at, counted, heard and replayed", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local bot: Bot = mock:addBot("Helper")
		local server: any, failures: { string }, runtime: Runtime = serve("Events", mock)
		local client: any = Generated.module("Client", MODULES.Events.client, mock:connectBot(bot))
		local seen: { string } = {}
		local heard: { number } = {}

		runtime:onJoin(function (player: any)
			table.insert(seen, player.Name)
		end)
		client.Sync.on(function (value: number)
			table.insert(heard, value)
		end)

		server.Sync.fire(bot, 3)
		mock:step()

		expect(`{table.concat(seen, ",")} {runtime:stats(bot).messagesOut} {table.concat(heard, ",")}`).is("Helper 1 3")
		expect(#failures).is(0)
	end)

	test("a bot whose client starts before its scope's server is heard once that server starts", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local bot: Bot = mock:addBot("Helper")
		local client: any = Generated.module("Client", MODULES.Events.client, mock:connectBot(bot))
		local ready: number = 0

		-- The bot's first frame sends its handshake with no server to hear it, so it waits for one
		mock:step()

		local server: any, failures: { string } = serve("Events", mock)

		server.Ready.on(function ()
			ready += 1
		end)
		client.Ready.fire()
		mock:step()
		mock:step()

		expect(ready).is(1)
		expect(table.concat(failures, ",")).is("")
	end)

	test("onHandshake runs once for each handshake accepted and never for a refused one", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local _, aliceSide = mock:join("Alice")
		local _, bobSide = mock:join("Bob")
		local _, _, runtime: Runtime = serve("Events", mock)
		local client: any = Generated.module("Client", MODULES.Events.client, aliceSide)
		local seen: { string } = {}

		runtime:onHandshake(function (player: any)
			table.insert(seen, player.Name)
		end)

		bobSide.reliable(nil, handshake(WRONG_HASH))
		client.Ready.fire()
		held(mock)
		client.Ready.fire()
		held(mock)

		expect(table.concat(seen, ",")).is("Alice")
	end)

	test(
		"traffic counts a player's bytes across every runtime on the hub, and what is written but not flushed",
		function ()
			local mock: Mock = Volt.mock(task.spawn)
			local alice = mock:join("Alice")
			local first: any, _, firstRuntime: Runtime = serve("Broadcasts", mock)
			local second: any, _, secondRuntime: Runtime = serve("Broadcasts", mock)
			local bot: Bot = mock:addBot("Helper")
			local hit: Hit = { target = 1, amount = 1 }

			first.Damage.fire(bot, hit)
			second.Damage.fire(bot, hit)
			first.Damage.fire(alice, hit)

			local _, written: number = firstRuntime:traffic(bot)

			mock:step()

			local sent: number, pending: number = secondRuntime:traffic(bot)
			local aliceSent: number, aliceHeld: number = firstRuntime:traffic(alice)

			expect(`{written} {sent} {pending}`).is(`{2 * DAMAGE_BYTES} {2 * DAMAGE_BYTES} 0`)
			expect(`{aliceSent} {aliceHeld}`).is(`0 {DAMAGE_BYTES}`)
		end
	)
end)
