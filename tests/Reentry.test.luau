--[[
    Proves the runtime holds when what it calls out to calls back into it
    part way through: a failure handler that fires or broadcasts from a
    message the cap dropped, a join callback that subscribes another, and
    a handshake callback that fires and flushes
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

type Mock = Volt.Mock
type Runtime = Volt.Runtime

type Hit = { target: number, amount: number }

-- A capped server with Alice and Bob handshaken, and what each one's client heard by name
type Harness = {
	mock: Mock,
	server: any,
	runtime: Runtime,
	alice: any,
	bob: any,
	heard: { [string]: { number } },
}

local ANSWER: number = 100 -- What the failure handler fires at Bob, which no other fire here does

local CLIENT: string = Served.modules.Capped.client -- Broadcasts with room for two Damage messages a frame
local SERVER: string = Served.modules.Capped.server
local EVENTS: string = Served.modules.Events.server

-- Enough steps for a client's handshake to be read and a server fire to arrive after it
local function steps(mock: Mock)
	mock:step()
	mock:step()
	mock:step()
end

local function setup(): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local server: any, runtime: Runtime = Generated.module("Server", SERVER, mock.server)
	local heard: { [string]: { number } } = { Alice = {}, Bob = {} }
	local players: { any } = {}

	for _, name: string in { "Alice", "Bob" } do
		local player: any, transport: Volt.Transport = mock:join(name)
		local client: any = Generated.module("Client", CLIENT, transport)

		client.Damage.on(function (hit: Hit)
			table.insert(heard[name], hit.amount)
		end)

		table.insert(players, player)
	end

	steps(mock)

	return { mock = mock, server = server, runtime = runtime, alice = players[1], bob = players[2], heard = heard }
end

-- The first outgoing failure is answered with a fire at Bob, the way the one handed in fires
local function answer(harness: Harness, fire: (bob: any, hit: Hit) -> ())
	local answered: boolean = false

	harness.server.onFailure(function (_, kind: string)
		if kind == "outgoing" and not answered then
			answered = true
			fire(harness.bob, { target = 1, amount = ANSWER })
		end
	end)
end

-- What each player heard, then the messages counted out for each
local function outcome(harness: Harness): string
	local alice: Volt.Stats, bob: Volt.Stats = harness.runtime:stats(harness.alice), harness.runtime:stats(harness.bob)
	local heard: string = `{table.concat(harness.heard.Alice, ",")} {table.concat(harness.heard.Bob, ",")}`

	return `{heard} {alice.messagesOut} {bob.messagesOut}`
end

describe("Reentry", function ()
	test("a handler that fires at Bob from a drop mid fire leaves the rest of Alice's message with Alice", function ()
		local harness: Harness = setup()

		answer(harness, harness.server.Damage.fire)

		-- The fourth fire's begin drops the third, and the flush drops the fourth
		for amount: number = 1, 4 do
			harness.server.Damage.fire(harness.alice, { target = 1, amount = amount })
		end

		steps(harness.mock)

		expect(outcome(harness)).is(`1,2 {ANSWER} 2 1`)
	end)

	test("a handler that broadcasts from a drop mid broadcast leaves every copy whole", function ()
		local harness: Harness = setup()

		answer(harness, function (bob: any, hit: Hit)
			harness.server.Damage.fireList({ bob }, hit)
		end)

		for amount: number = 1, 3 do
			harness.server.Damage.fire(harness.alice, { target = 1, amount = amount })
		end

		-- Bob's copy is made first, so a handler run during Alice's would write over what his holds
		harness.server.Damage.fireList({ harness.bob, harness.alice }, { target = 1, amount = 5 })
		steps(harness.mock)

		expect(outcome(harness)).is(`1,2 5,{ANSWER} 2 2`)
	end)

	test(
		"a handler told of a flush's drop is told once the flush is done, so a joiner it fires at waits whole",
		function ()
			local harness: Harness = setup()
			local carol: any = nil

			-- A join adds a state, which the flush must not be walking when it does
			harness.server.onFailure(function (_, kind: string)
				if kind == "outgoing" and not carol then
					carol = harness.mock:join("Carol")
					harness.server.Damage.fire(carol, { target = 1, amount = ANSWER })
				end
			end)

			-- Three fires take Alice past the cap with no begin after them, so the flush is what drops the third
			for amount: number = 1, 3 do
				harness.server.Damage.fire(harness.alice, { target = 1, amount = amount })
			end

			steps(harness.mock)

			expect(outcome(harness)).is("1,2  2 0")
			expect(harness.runtime:stats(carol).messagesOut).is(1)
		end
	)

	test(
		"an onJoin subscribed from inside a join callback hears the joiner once, and none is skipped or doubled",
		function ()
			local mock: Mock = Volt.mock(task.spawn)
			local _, runtime: Runtime = Generated.module("Server", EVENTS, mock.server)
			local heard: { number } = { 0, 0, 0, 0, 0 }

			-- A subscriber that counts the joins it hears in its own place
			local function counter(index: number): (player: any) -> ()
				return function ()
					heard[index] += 1
				end
			end

			runtime:onJoin(function ()
				heard[1] += 1

				if heard[1] == 1 then
					runtime:onJoin(counter(4))
					runtime:onJoin(counter(5))
				end
			end)
			runtime:onJoin(counter(2))
			runtime:onJoin(counter(3))
			mock:join("Alice")

			expect(table.concat(heard, ",")).is("1,1,1,1,1")
		end
	)

	test("an onHandshake callback that fires and flushes sends its fire in the same step as what was held", function ()
		local mock: Mock = Volt.mock(task.spawn)
		local server: any, runtime: Runtime = Generated.module("Server", SERVER, mock.server)
		local alice, transport = mock:join("Alice")
		local heard: { number } = {}
		local announced: { number } = { 0, 0, 0 }

		-- The flush it calls is a whole one, which must not announce this handshake a second time
		runtime:onHandshake(function (player: any)
			announced[1] += 1
			server.Damage.fire(player, { target = 1, amount = 3 })
			server.flush()
		end)

		for index: number = 2, 3 do
			runtime:onHandshake(function ()
				announced[index] += 1
			end)
		end

		-- Two fill her held frame to the cap, so a third written behind them would be dropped
		for amount: number = 1, 2 do
			server.Damage.fire(alice, { target = 1, amount = amount })
		end

		mock:step()

		local client: any = Generated.module("Client", CLIENT, transport)

		client.Damage.on(function (hit: Hit)
			table.insert(heard, hit.amount)
		end)

		-- Her handshake is read at the second step, and what its flush sent arrives at the third
		mock:step()
		mock:step()
		expect(#heard).is(0)

		mock:step()
		expect(table.concat(heard, ",")).is("1,2,3")
		expect(table.concat(announced, ",")).is("1,1,1")
		expect(runtime:stats(alice).failures.outgoing).is(nil)
	end)
end)
