--[[
    What the tests of channels and the stamp run over: Streams.volt's
    modules, compiled as written or with options before its text, a server
    and Alice's client over one mock on transports that keep what each
    side fires, with every failure kept, and the steps, packets and calls
    the cases read
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Generated = require("./Generated")
local hex = require("./Hex")
local tapped = require("./Tapped")
local Volt = require("@volt")

export type Fired = tapped.Fired
type Mock = Volt.Mock
type Transport = Volt.Transport

export type Report = { player: any, kind: string, detail: string } -- One failure a side reported
export type Modules = { client: string, server: string } -- One schema's modules, as a side loads them

-- A server and Alice's client over one mock, each running its side's module over a transport that keeps what it fires
export type Harness = {
	mock: Mock,
	alice: any,
	transport: Transport, -- Alice's client side, tapped, which her client starts on
	modules: Modules,
	server: any,
	client: any,
	fired: { server: { Fired }, client: { Fired } },
	failures: { server: { Report }, client: { Report } },
}

-- The results of a call once it is back, as one line, or pending until then
export type Box = { line: string }

local SCHEMA: string = fs.readFile("tests/Schemas/Streams.volt")
local CLIENT: string, SERVER: string, TYPES: string = Generated.modules("Streams", SCHEMA)

local Streamed = {
	sides = { { name = "Client", text = CLIENT }, { name = "Server", text = SERVER }, { name = "Types", text = TYPES } },
	hash = (select(2, Generated.compile("Streams", SCHEMA))) :: number,
}

-- A test schema's modules, Streams' unless another is named, compiled with the options given before its text
function Streamed.compiled(options: string, name: string?): Modules
	local schema: string = name or "Streams"
	local text: string = fs.readFile(`tests/Schemas/{schema}.volt`)
	local client: string, server: string = Generated.modules(schema, `{options}\n{text}`)

	return { client = client, server = server }
end

-- A list that keeps every failure a module reports, with the player it names
local function recorded(module: any): { Report }
	local reports: { Report } = {}

	module.onFailure(function (player: any, kind: string, detail: string)
		table.insert(reports, { player = player, kind = kind, detail = detail })
	end)

	return reports
end

-- A server module over a mock with Alice joined, before her client starts
function Streamed.serve(modules: Modules?): Harness
	local used: Modules = modules or { client = CLIENT, server = SERVER }
	local mock: Mock = Volt.mock(task.spawn)
	local alice: any, transport: Transport = mock:join("Alice")
	local fired: { server: { Fired }, client: { Fired } } = { server = {}, client = {} }
	local server: any = Generated.module("Server", used.server, tapped(mock.server, fired.server))

	return {
		mock = mock,
		alice = alice,
		transport = tapped(transport, fired.client),
		modules = used,
		server = server,
		client = nil,
		fired = fired,
		failures = { server = recorded(server), client = {} },
	}
end

-- Starts Alice's client module on her side of the mock
function Streamed.start(harness: Harness): Harness
	harness.client = Generated.module("Client", harness.modules.client, harness.transport)
	harness.failures.client = recorded(harness.client)

	return harness
end

function Streamed.steps(harness: Harness, count: number)
	for _ = 1, count do
		harness.mock:step()
	end
end

-- Alice's client starts and its handshake is flushed and read, and what either side fired so far is forgotten
function Streamed.connected(modules: Modules?): Harness
	local harness: Harness = Streamed.start(Streamed.serve(modules))

	Streamed.steps(harness, 2)
	table.clear(harness.fired.server)
	table.clear(harness.fired.client)

	return harness
end

-- Each packet a side fired, as its remote's initial and its hex, one a line
function Streamed.lines(fired: { Fired }): string
	local list: { string } = {}

	for _, entry: Fired in fired do
		table.insert(list, `{entry.remote} {hex(entry.packet)}`)
	end

	return table.concat(list, "\n")
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
function Streamed.into(box: Box, invoke: (...any) -> ...any, ...: any)
	task.spawn(function (...: any)
		box.line = line(invoke(...))
	end, ...)
end

return Streamed
