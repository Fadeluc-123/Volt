--[[
    Proves functions end to end: each side of the Functions schema renders
    as its golden file, compiler and runtime agree on what a refusal holds,
    and over the mock a call is answered, refused by a missing or failing
    handler, settled as a promise or refused at the call, preceded by its
    handler's fires, disconnected, and failed at once when the cap drops it
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local golden = require("./Expected")
local Volt = require("@volt")
local Config = require("@volt/Config/Runtime")
local Wire = require("@volt/Compiler/Config/Wire")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock
type Report = { kind: string, detail: string } -- One failure the server reported

-- A server and one client over one mock, each running the generated module of its side
type Harness = {
	mock: Mock,
	server: any,
	client: any,
	failures: { Report },
	reported: { string }, -- Each failure the client reported, as its player, its kind and its detail
}

-- The results of a call once its reply is back, as one line, or pending until then
type Box = { line: string }

local CAP: number = 32 -- The capped modules' maxPacket: a handshake, a Divide and an Inventory.Transfer fit, no more
local PAST_SLOTS: number = Config.slots + 1 -- One drop more than a function has slots, so slots kept would run out
local DROPPED: string = "nil outgoing over maxPacket, a message was dropped" -- A dropped call as the client reports it

local SCHEMA: string = fs.readFile("tests/Schemas/Functions.volt")
local CLIENT: string, SERVER: string, TYPES: string = Generated.modules("Functions", SCHEMA)
local CAPPED_CLIENT: string, CAPPED_SERVER: string =
	Generated.modules("Functions", `option maxPacket = {CAP}\n{SCHEMA}`)
local EXAMPLE_CLIENT: string, EXAMPLE_SERVER: string =
	Generated.modules("Example", fs.readFile("tests/Schemas/Example.volt"))
local SIDES: { { name: string, text: string } } =
	{ { name = "Client", text = CLIENT }, { name = "Server", text = SERVER }, { name = "Types", text = TYPES } }

local function setup(client: string?, server: string?): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local _, transport = mock:join("Alice")
	local failures: { Report } = {}
	local reported: { string } = {}
	local serverModule: any = Generated.module("Server", server or SERVER, mock.server)

	serverModule.onFailure(function (_, kind: string, detail: string)
		table.insert(failures, { kind = kind, detail = detail })
	end)

	local clientModule: any = Generated.module("Client", client or CLIENT, transport)

	clientModule.onFailure(function (player: any, kind: string, detail: string)
		table.insert(reported, `{player} {kind} {detail}`)
	end)

	return {
		mock = mock,
		server = serverModule,
		client = clientModule,
		failures = failures,
		reported = reported,
	}
end

-- Values as one line, as a call returned them or a promise settled with them
local function line(results: { n: number, [number]: any }): string
	local parts: { string } = {}

	for index: number = 1, results.n do
		table.insert(parts, tostring(results[index]))
	end

	return table.concat(parts, " ")
end

-- Makes one call into a box on a thread of its own, since a coroutine call yields, rendering its returns once back
local function into(box: Box, invoke: (...any) -> ...any, ...: any): Box
	task.spawn(function (...: any)
		box.line = line(table.pack(invoke(...)))
	end, ...)

	return box
end

local function call(invoke: (...any) -> ...any, ...: any): Box
	return into({ line = "pending" }, invoke, ...)
end

-- Connects a handler to every function a dropped-call test calls: Echo doubles, Divide divides and a transfer moves
local function answer(harness: Harness)
	harness.server.Echo.on(function (_, value: number): number
		return value * 2
	end)
	harness.server.Divide.on(function (_, dividend: number, divisor: number): (boolean, number?)
		return true, dividend / divisor
	end)
	harness.server.Inventory.Transfer.on(function (_, source: number, destination: number, quantity: number)
		return source < destination, `moved {quantity}`
	end)
end

-- The client reported one failure per dropped call, each the cap's with no player, and the server reported none
local function dropsOnly(harness: Harness, count: number)
	local others: number = 0

	for _, report: string in harness.reported do
		if report ~= DROPPED then
			others += 1
		end
	end

	expect(#harness.reported).is(count)
	expect(others).is(0)
	expect(harness.client.stats().failures.outgoing).is(count)
	expect(#harness.failures).is(0)
end

-- One step flushes the call, the next delivers it and flushes the reply, the last delivers the reply
local function roundTrip(mock: Mock)
	mock:step()
	mock:step()
	mock:step()
end

describe("Functions", function ()
	for _, side in SIDES do
		test(`renders the {side.name:lower()} module as its golden file`, function ()
			expect(golden("tests/Golden/Functions", side.name, side.text)).is(side.text)
		end)
	end

	test("agrees with the runtime on what a refusal carries", function ()
		expect(Wire.replyMessage).is(Config.messageBytes)
	end)

	describe("over the mock", function ()
		test("a call reaches the handler with the player first and its returns come back after ok", function ()
			local harness: Harness = setup()
			local heard: string? = nil

			harness.server.Echo.on(function (player: any, value: number): number
				heard = `{player.Name} {value}`
				return value * 2
			end)

			local box: Box = call(harness.client.Echo.invoke, 21)
			roundTrip(harness.mock)

			expect(heard).is("Alice 21")
			expect(box.line).is("true 42")
		end)

		test("a call with nothing either way comes back as ok alone", function ()
			local harness: Harness = setup()
			local called: number = 0

			harness.server.Ping.on(function ()
				called += 1
			end)

			local box: Box = call(harness.client.Ping.invoke)
			roundTrip(harness.mock)

			expect(called).is(1)
			expect(box.line).is("true")
		end)

		test("returns with flag bits come back as sent, the absent optional included", function ()
			local harness: Harness = setup()
			local whole: boolean = true

			harness.server.Divide.on(function (_, dividend: number, divisor: number): (boolean, number?)
				return divisor ~= 0, divisor ~= 0 and dividend / divisor or nil
			end)

			local exact: Box = call(harness.client.Divide.invoke, 5, 2)
			local byZero: Box = call(harness.client.Divide.invoke, 5, 0)
			roundTrip(harness.mock)

			expect(whole).is(true)
			expect(exact.line).is("true true 2.5")
			expect(byZero.line).is("true false nil")
		end)

		test("a call with no handler is refused at once", function ()
			local harness: Harness = setup()
			local box: Box = call(harness.client.Divide.invoke, 1, 1)

			roundTrip(harness.mock)

			expect(box.line).is("false no handler")
			expect(#harness.failures).is(0)
		end)

		test("a handler's error refuses the call with its message and is a handler failure", function ()
			local harness: Harness = setup()

			harness.server.Echo.on(function ()
				error("boom")
			end)

			local box: Box = call(harness.client.Echo.invoke, 1)
			roundTrip(harness.mock)

			expect(box.line).is("false boom")
			expect(#harness.failures).is(1)
			expect(harness.failures[1].kind).is("handler")
			expect((harness.failures[1].detail:find("Echo: ", 1, true))).is(1)
		end)

		test("a return the function cannot carry refuses the call with the refusal and is a handler failure", function ()
			local harness: Harness = setup()

			harness.server.Echo.on(function (): any
				return "x"
			end)

			local box: Box = call(harness.client.Echo.invoke, 1)
			roundTrip(harness.mock)

			expect(box.line).is("false Echo: expected u8")
			expect(#harness.failures).is(1)
			expect(harness.failures[1].kind).is("handler")
			expect(harness.failures[1].detail).is("Echo: expected u8")
		end)

		test("a promise rejects with the reason and resolves with the returns", function ()
			local harness: Harness = setup()
			local rejected = harness.client.Inventory.Transfer.invoke(1, 2, 3)

			roundTrip(harness.mock)

			harness.server.Inventory.Transfer.on(function (_, source: number, destination: number, quantity: number)
				return source < destination, `moved {quantity}`
			end)

			local resolved = harness.client.Inventory.Transfer.invoke(1, 2, 3)
			roundTrip(harness.mock)

			expect(table.concat({ tostring(rejected.settled[1]), rejected.settled[2] }, " ")).is("false no handler")
			expect(
				table.concat({ tostring(resolved.settled[1]), tostring(resolved.settled[2]), resolved.settled[3] }, " ")
			).is("true true moved 3")
		end)

		test("a promise rejects with exactly the handler's error, its position cut", function ()
			local harness: Harness = setup()

			harness.server.Inventory.Transfer.on(function ()
				error("boom")
			end)

			local promise = harness.client.Inventory.Transfer.invoke(1, 2, 3)
			roundTrip(harness.mock)

			expect(`{promise.settled[1]} {promise.settled[2]}`).is("false boom")
			expect(harness.failures[1].kind).is("handler")
		end)

		test("an argument the call's writer refuses raises at invoke, before a promise exists", function ()
			local harness: Harness = setup()
			local ok: boolean, message: any = pcall(harness.client.Inventory.Transfer.invoke, 300, 2, 3)

			expect(ok).is(false)
			expect(message).is("Inventory.Transfer.source: expected u8")
		end)

		test(
			"a handler's fires at its caller arrive before its reply, so the listener has run when it settles",
			function ()
				local mock: Mock = Volt.mock(task.spawn)
				local _, transport = mock:join("Alice")
				local server: any = Generated.module("Server", EXAMPLE_SERVER, mock.server)
				local client: any = Generated.module("Client", EXAMPLE_CLIENT, transport)
				local seen: { string } = {}
				local promise: any = nil

				client.Inventory.Patch.on(function (patch: { version: number })
					table.insert(seen, `{patch.version} {promise.settled == nil}`)
				end)
				server.Inventory.Transfer.on(function (player: any): (boolean, string?)
					server.Inventory.Patch.fire(player, { version = 1, set = {}, cleared = {} })
					server.Inventory.Patch.fire(player, { version = 2, set = {}, cleared = {} })
					return true, nil
				end)

				promise = client.Inventory.Transfer.invoke("bag", "chest", 1, 1)
				roundTrip(mock)

				expect(table.concat(seen, ",")).is("1 true,2 true")
				expect(promise.settled[1]).is(true)
			end
		)

		test("the handler's disconnect leaves the next call unhandled", function ()
			local harness: Harness = setup()
			local disconnect: () -> () = harness.server.Ping.on(function () end)

			disconnect()

			local box: Box = call(harness.client.Ping.invoke)
			roundTrip(harness.mock)

			expect(box.line).is("false no handler")
		end)
	end)

	describe("a call the client's cap drops", function ()
		test("fails at once in coroutine mode, its failure heard first, and the next call still fits", function ()
			local harness: Harness = setup(CAPPED_CLIENT, CAPPED_SERVER)
			local second: Box = { line = "pending" }
			local heard: string? = nil -- The second call's line when its failure reached the handler

			answer(harness)
			harness.client.onFailure(function (player: any, kind: string, detail: string)
				table.insert(harness.reported, `{player} {kind} {detail}`)
				heard = second.line
			end)

			-- The handshake and a Divide take 24 bytes; a second Divide would take 43, and an Echo after it takes 28
			local first: Box = call(harness.client.Divide.invoke, 5, 2)
			into(second, harness.client.Divide.invoke, 1, 1)
			local echo: Box = call(harness.client.Echo.invoke, 21)

			expect(heard).is("pending")
			expect(second.line).is("false dropped")

			roundTrip(harness.mock)

			expect(first.line).is("true true 2.5")
			expect(echo.line).is("true 42")
			dropsOnly(harness, 1)
		end)

		test("is a promise already rejected as the frame's last write, and the calls before it are answered", function ()
			local harness: Harness = setup(CAPPED_CLIENT, CAPPED_SERVER)

			answer(harness)

			-- The handshake, a Divide and a transfer take 31 bytes; a second transfer would take 38
			local divide: Box = call(harness.client.Divide.invoke, 5, 2)
			local transfer = harness.client.Inventory.Transfer.invoke(1, 2, 3)
			local dropped = harness.client.Inventory.Transfer.invoke(1, 2, 3)

			expect(line(dropped.settled)).is("false dropped")

			roundTrip(harness.mock)

			expect(divide.line).is("true true 2.5")
			expect(line(transfer.settled)).is("true true moved 3")
			dropsOnly(harness, 1)
		end)

		test("gives its slot back, so past more drops than slots the next frame's call goes out", function ()
			local harness: Harness = setup(CAPPED_CLIENT, CAPPED_SERVER)
			local rejected: number = 0

			answer(harness)

			local divide: Box = call(harness.client.Divide.invoke, 5, 2)
			local transfer = harness.client.Inventory.Transfer.invoke(1, 2, 3)

			for _ = 1, PAST_SLOTS do
				if line(harness.client.Inventory.Transfer.invoke(1, 2, 3).settled) == "false dropped" then
					rejected += 1
				end
			end

			roundTrip(harness.mock)

			local later = harness.client.Inventory.Transfer.invoke(1, 2, 3)
			roundTrip(harness.mock)

			expect(rejected).is(PAST_SLOTS)
			expect(divide.line).is("true true 2.5")
			expect(line(transfer.settled)).is("true true moved 3")
			expect(line(later.settled)).is("true true moved 3")
			dropsOnly(harness, PAST_SLOTS)
		end)
	end)
end)
