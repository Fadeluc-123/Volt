--[[
    Proves functions the server calls: each side of the Prompts schema
    renders as its golden file, the server's entries with invoke and the
    client's with on and connected, every one in its side's functions map;
    and over the mock a call to Alice is answered on the thread and as a
    promise, refused by her handler's error or by no handler, preceded by
    her handler's fires, held until her client starts, dropped at the cap
    and answered by a bot in one step
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
type Runtime = Volt.Runtime
type Transport = Volt.Transport

type Report = { player: any, kind: string, detail: string } -- One failure a side reported

-- A server over one mock with Alice joined, and her client once it starts, each running its side's module
type Harness = {
	mock: Mock,
	alice: any,
	transport: Transport, -- Alice's client side, which her client starts on
	server: any,
	runtime: Runtime, -- The server's, whose slot tables a test reads
	client: any,
	failures: { server: { Report }, client: { Report } },
}

-- The results of a call once it is back, as one line, or pending until then
type Box = { line: string }

local Vector3 = Environment.Vector3

local CAP: number = 16 -- The capped modules' maxOutgoing: a Confirm call with a title of 11 bytes fits, one of 12 does not
local CROSSING: string = "Sell 3 wood?" -- A title of 12 bytes, so its Confirm call takes 17 and crosses the cap
local CONFIRM: number = 2 -- The id Confirm's reply reaches the server with, which keys its slot tables

local SCHEMA: string = fs.readFile("tests/Schemas/Prompts.volt")
local CLIENT: string, SERVER: string, TYPES: string = Generated.modules("Prompts", SCHEMA)
local CAPPED_CLIENT: string, CAPPED_SERVER: string =
	Generated.modules("Prompts", `option maxOutgoing = {CAP}\n{SCHEMA}`)
local SIDES: { { name: string, text: string } } =
	{ { name = "Client", text = CLIENT }, { name = "Server", text = SERVER }, { name = "Types", text = TYPES } }

-- A list that keeps every failure a module reports, with the player it names
local function recorded(module: any): { Report }
	local reports: { Report } = {}

	module.onFailure(function (player: any, kind: string, detail: string)
		table.insert(reports, { player = player, kind = kind, detail = detail })
	end)

	return reports
end

-- A server module over a mock with Alice joined, before her client starts
local function serve(server: string?): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local alice: any, transport: Transport = mock:join("Alice")
	local module: any, runtime: Runtime = Generated.module("Server", server or SERVER, mock.server)

	return {
		mock = mock,
		alice = alice,
		transport = transport,
		server = module,
		runtime = runtime,
		client = nil,
		failures = { server = recorded(module), client = {} },
	}
end

-- Starts Alice's client module on her side of the mock
local function start(harness: Harness, client: string?): Harness
	harness.client = Generated.module("Client", client or CLIENT, harness.transport)
	harness.failures.client = recorded(harness.client)

	return harness
end

-- Values as one line, as a call returned them
local function line(...: any): string
	local parts: { string } = {}

	for index: number = 1, select("#", ...) do
		table.insert(parts, tostring((select(index, ...))))
	end

	return table.concat(parts, " ")
end

-- Makes one call into a box on a thread of its own, since a coroutine call yields, rendering its returns once back
local function into(box: Box, invoke: (...any) -> ...any, ...: any): Box
	task.spawn(function (...: any)
		box.line = line(invoke(...))
	end, ...)

	return box
end

local function call(invoke: (...any) -> ...any, ...: any): Box
	return into({ line = "pending" }, invoke, ...)
end

-- Accepts every Confirm with the note ok
local function accept(client: any)
	client.Confirm.on(function (): (boolean, string?)
		return true, "ok"
	end)
end

--[[
    One step flushes Alice's handshake, the next reads it and sends what
    was held for her, the next delivers the call and flushes the reply,
    and the last delivers the reply
--]]

local function answer(mock: Mock)
	for _ = 1, 4 do
		mock:step()
	end
end

describe("Prompts", function ()
	for _, side in SIDES do
		test(`renders the {side.name:lower()} module as its golden file`, function ()
			expect(golden("tests/Golden/Prompts", side.name, side.text)).is(side.text)
		end)
	end

	describe("over the mock", function ()
		test("a call reaches Alice's handler with the values alone and comes back as ok and the returns", function ()
			local harness: Harness = start(serve())
			local heard: string? = nil

			harness.client.Confirm.on(function (title: string, seconds: number, extra: any): (boolean, string?)
				heard = `{title} {seconds} {extra}`
				return true, "ok"
			end)

			local box: Box = call(harness.server.Confirm.invoke, harness.alice, "Sell?", 10)
			answer(harness.mock)

			expect(`{heard} {box.line}`).is("Sell? 10 nil true true ok")
			expect(#harness.failures.server + #harness.failures.client).is(0)
		end)

		test("a promise call resolves with the Vector3 the client's handler returns", function ()
			local harness: Harness = start(serve())

			harness.client.Camera.Aim.on(function (): any
				return Vector3.new(1, 2, 3)
			end)

			local promise: any = harness.server.Camera.Aim.invoke(harness.alice)
			answer(harness.mock)

			expect(promise.settled[1]).is(true)
			expect(promise.settled[2] == Vector3.new(1, 2, 3)).is(true)
		end)

		test("a client handler's error is a handler failure with no player, and the caller gets its text", function ()
			local harness: Harness = start(serve())

			harness.client.Camera.Aim.on(function ()
				error("boom")
			end)
			harness.client.Confirm.on(function ()
				error("boom")
			end)

			local promise: any = harness.server.Camera.Aim.invoke(harness.alice)
			local box: Box = call(harness.server.Confirm.invoke, harness.alice, "Sell?", 10)
			answer(harness.mock)

			local report: Report = harness.failures.client[1]
			local name: string? = report.detail:match("^(.-): ")

			expect(`{#harness.failures.client} {report.player} {report.kind} {name}`).is("2 nil handler Camera.Aim")
			expect(`{promise.settled[1]} {promise.settled[2]}, {box.line}`).is("false boom, false boom")
		end)

		test("connected reads false before on, true after it and false after its disconnect", function ()
			local confirm: any = start(serve()).client.Confirm
			local before: boolean = confirm.connected()
			local disconnect: () -> () = confirm.on(function () end)
			local during: boolean = confirm.connected()

			disconnect()

			expect(`{before} {during} {confirm.connected()}`).is("false true false")
		end)

		test("a call with no handler connected comes back as no handler", function ()
			local harness: Harness = start(serve())
			local box: Box = call(harness.server.Confirm.invoke, harness.alice, "Sell?", 10)

			answer(harness.mock)

			expect(box.line).is("false no handler")
			expect(#harness.failures.client).is(0)
		end)

		test(
			"a handler's fires at the server arrive before its reply, so the listener has run when invoke returns",
			function ()
				local harness: Harness = start(serve())
				local box: Box = { line = "pending" }
				local seen: { string } = {}

				harness.server.Progress.on(function (_, value: number)
					table.insert(seen, `{value} {box.line}`)
				end)
				harness.client.Confirm.on(function (): (boolean, string?)
					harness.client.Progress.fire(1)
					harness.client.Progress.fire(2)
					return true, nil
				end)

				into(box, harness.server.Confirm.invoke, harness.alice, "Sell?", 10)
				answer(harness.mock)

				expect(table.concat(seen, ",")).is("1 pending,2 pending")
				expect(box.line).is("true true nil")
			end
		)

		test("a call at Alice before her client starts is held, then answered after her handshake", function ()
			local harness: Harness = serve()
			local box: Box = call(harness.server.Confirm.invoke, harness.alice, "Sell?", 10)

			harness.mock:step()
			harness.mock:step()
			expect(box.line).is("pending")

			accept(start(harness).client)
			answer(harness.mock)

			expect(box.line).is("true true ok")
		end)

		test(
			"a call past the cap fails at once with one outgoing failure for Alice, and the next takes its slot",
			function ()
				local harness: Harness = start(serve(CAPPED_SERVER), CAPPED_CLIENT)
				local failures: { Report } = harness.failures.server

				accept(harness.client)

				local dropped: Box = call(harness.server.Confirm.invoke, harness.alice, CROSSING, 10)

				expect(dropped.line).is("false dropped")
				expect(`{#failures} {failures[1].player == harness.alice} {failures[1].kind} {failures[1].detail}`).is(
					"1 true outgoing over maxOutgoing, a message was dropped"
				)

				local after: Box = call(harness.server.Confirm.invoke, harness.alice, "Sell?", 10)
				local slots: any = (harness.runtime :: any)._players[harness.alice].calls[CONFIRM]

				expect(`{slots.last} {slots.pending[1] ~= nil}`).is("1 true")

				answer(harness.mock)

				expect(after.line).is("true true ok")
				expect(#failures).is(1)
			end
		)

		test("a bot whose client runs on its connectBot transport answers in the step the call goes out", function ()
			local harness: Harness = serve()
			local bot: Volt.Bot = harness.mock:addBot("Helper")
			local client: any = Generated.module("Client", CLIENT, harness.mock:connectBot(bot))

			accept(client)

			-- The bot's first frame hands its handshake straight to the server
			harness.mock:step()

			local box: Box = call(harness.server.Confirm.invoke, bot, "Sell?", 10)
			harness.mock:step()

			expect(box.line).is("true true ok")
		end)
	end)
end)
