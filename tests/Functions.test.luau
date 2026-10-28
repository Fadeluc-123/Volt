--[[
    Proves functions end to end: each side of the Functions schema renders
    as its golden file, the runtime agrees on what a refusal carries, and
    over the mock a call reaches its handler and its returns come back, a
    missing or failing handler refuses it, a promise settles either way or
    refuses at the call, a handler's fires come first, and it disconnects
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
}

-- The results of a call once its reply is back, as one line, or pending until then
type Box = { line: string }

local SCHEMA: string = fs.readFile("tests/Schemas/Functions.volt")
local CLIENT: string, SERVER: string, TYPES: string = Generated.modules("Functions", SCHEMA)
local EXAMPLE_CLIENT: string, EXAMPLE_SERVER: string =
	Generated.modules("Example", fs.readFile("tests/Schemas/Example.volt"))
local SIDES: { { name: string, text: string } } =
	{ { name = "Client", text = CLIENT }, { name = "Server", text = SERVER }, { name = "Types", text = TYPES } }

local function setup(): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local _, transport = mock:join("Alice")
	local failures: { Report } = {}
	local server: any = Generated.module("Server", SERVER, mock.server)

	server.onFailure(function (_, kind: string, detail: string)
		table.insert(failures, { kind = kind, detail = detail })
	end)

	return {
		mock = mock,
		server = server,
		client = Generated.module("Client", CLIENT, transport),
		failures = failures,
	}
end

-- Makes one call on a thread of its own, since a coroutine call yields, and renders what it returned once it is back
local function call(invoke: (...any) -> ...any, ...: any): Box
	local box: Box = { line = "pending" }

	task.spawn(function (...: any)
		local results = table.pack(invoke(...))
		local parts: { string } = {}

		for index: number = 1, results.n do
			table.insert(parts, tostring(results[index]))
		end

		box.line = table.concat(parts, " ")
	end, ...)

	return box
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
end)
