--[[
    Proves when onHandshake runs, over the mock and the generated modules:
    at the end of the first flush after a handshake is accepted, once that
    flush has sent what was held and reported what it dropped, in the order
    handshakes are read, never for a player who left first, and for a bot
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local Served = require("./Served")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect
local serve = Served.serve
local held = Served.held

type Bot = Volt.Bot
type Mock = Volt.Mock
type Runtime = Volt.Runtime

type Hit = { target: number, amount: number }

local MODULES = Served.modules

describe("Handshakes", function ()
	test(
		"a drop the releasing flush finds is reported first, and a fire inside the callback follows what was held",
		function ()
			local mock: Mock = Volt.mock(task.spawn)
			local alice, transport = mock:join("Alice")
			local server: any, runtime: Runtime = Generated.module("Server", MODULES.Capped.server, mock.server)
			local log: { string } = {}
			local heard: { number } = {}

			server.onFailure(function (_, kind: string)
				table.insert(log, kind)
			end)
			server.onHandshake(function (player: any)
				table.insert(log, `handshake {player.Name}`)
				server.Damage.fire(player, { target = 1, amount = 4 })
			end)

			-- Two fill her held frame to the cap
			for amount: number = 1, 2 do
				server.Damage.fire(alice, { target = 1, amount = amount })
			end

			mock:step()

			local client: any = Generated.module("Client", MODULES.Capped.client, transport)

			client.Damage.on(function (hit: Hit)
				table.insert(heard, hit.amount)
			end)

			-- Her handshake is sent at this step, and a third fire takes her frame past the cap before it is read
			mock:step()
			server.Damage.fire(alice, { target = 1, amount = 3 })
			mock:step()

			expect(table.concat(log, ",")).is("outgoing,handshake Alice")

			mock:step()
			mock:step()

			expect(table.concat(heard, ",")).is("1,2,4")
			expect(runtime:stats(alice).failures.outgoing).is(1)
		end
	)

	test("a message riding in the handshake's packet is heard first, and the callback waits for the flush", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local server: any, failures: { string }, runtime: Runtime = serve("Events", mock)
		local _, transport = mock:join("Alice")
		local client: any = Generated.module("Client", MODULES.Events.client, transport)
		local log: { string } = {}

		server.Ready.on(function ()
			table.insert(log, `ready {runtime.frame}`)
		end)
		runtime:onHandshake(function ()
			table.insert(log, `handshake {runtime.frame}`)
		end)

		-- Fired before the client's first frame, so its first packet carries the handshake and then this
		client.Ready.fire()

		for _: number = 1, 4 do
			mock:step()
		end

		expect(table.concat(log, ",")).is("ready 1,handshake 2")
		expect(#failures).is(0)
	end)

	test("two handshakes read in one frame are announced at the end of one flush, in start order, once each", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local _, _, runtime: Runtime = serve("Events", mock)
		local _, aliceSide = mock:join("Alice")
		local _, bobSide = mock:join("Bob")
		local seen: { string } = {}

		runtime:onHandshake(function (player: any)
			table.insert(seen, `{player.Name} {runtime.frame}`)
		end)

		-- Bob's client starts first, so his handshake is sent and read first though Alice joined first
		Generated.module("Client", MODULES.Events.client, bobSide)
		Generated.module("Client", MODULES.Events.client, aliceSide)
		held(mock)
		held(mock)

		expect(table.concat(seen, ",")).is("Bob 2,Alice 2")
	end)

	test("a player kicked by a listener of their handshake's packet hears onLeave and never onHandshake", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local server: any, failures: { string }, runtime: Runtime = serve("Events", mock)
		local _, transport = mock:join("Alice")
		local client: any = Generated.module("Client", MODULES.Events.client, transport)
		local seen: { string } = {}

		server.Ready.on(function (player: any)
			player:Kick("not ready")
		end)
		runtime:onLeave(function (player: any)
			table.insert(seen, `left {player.Name}`)
		end)
		runtime:onHandshake(function (player: any)
			table.insert(seen, `handshake {player.Name}`)
		end)

		client.Ready.fire()
		held(mock)
		held(mock)

		expect(table.concat(seen, ",")).is("left Alice")
		expect(#failures).is(0)
	end)

	test(
		"a bot connected after the server is announced at the server's flush a step after its handshake is read",
		function ()
			local mock: Mock = Volt.mock(task.spawn)
			local _, _, runtime: Runtime = serve("Events", mock)
			local bot: Bot = mock:addBot("Helper")
			local seen: { string } = {}

			runtime:onHandshake(function (player: any)
				table.insert(seen, player.Name)
			end)

			-- Its client's frame comes after the server's, so the server reads its handshake once that step's flush is done
			Generated.module("Client", MODULES.Events.client, mock:connectBot(bot))
			mock:step()
			expect(`{runtime:stats(bot).packetsIn} {#seen}`).is("1 0")

			mock:step()
			expect(table.concat(seen, ",")).is("Helper")
		end
	)
end)
