--[[
    The harness the failure suites share: the modules of every schema
    they raise failures over, compiled unchecked, a server and one client
    over a mock with every failure each side reports kept in order, a
    packet from a list of bytes, the steps a fire or a call takes, and the
    check that a failure of one message names it once
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local Volt = require("@volt")

local expect = Suite.expect

type Mock = Volt.Mock
type Transport = Volt.Transport

export type Report = { player: any, kind: string, detail: string } -- One failure a side reported, with its player

-- A server and one client over a mock, each running its side's module, and what each side reported
export type Harness = {
	mock: Mock,
	player: any,
	transport: Transport, -- The player's client side, which a raw packet is sent through
	server: any,
	client: any,
	names: { [string]: boolean }, -- Every registry name either side has
	failures: { server: { Report }, client: { Report } },
}

-- Unchecked, so a value only a reader refuses can be sent; the reply path and the readers are checked in every build
local SCHEMAS: { string } = {
	"Events",
	"Functions",
	"Exports",
	"Records",
	"Example",
	"Console",
	"Prompts",
	"Streams",
	"Ordered",
	"Rotations",
	"Awaited",
	"Layouts",
	"Volumes",
	"Deltas",
	"Dictionary",
}
local CAP: number = 16 -- A player's frame in the capped Prompts, which a Confirm call with a title of 12 bytes crosses

local MODULES: { [string]: { client: string, server: string } } = {}

for _, name: string in SCHEMAS do
	local source: string = `option writeValidation = false\n{fs.readFile(`tests/Schemas/{name}.volt`)}`
	local client: string, server: string = Generated.modules(name, source)

	MODULES[name] = { client = client, server = server }
end

-- Prompts again under the cap, as Capped, so a server's call crosses it at its own invoke
local capped: string =
	`option maxOutgoing = {CAP}\noption writeValidation = false\n{fs.readFile("tests/Schemas/Prompts.volt")}`
local cappedClient: string, cappedServer: string = Generated.modules("Prompts", capped)

MODULES.Capped = { client = cappedClient, server = cappedServer }

-- What a failure suite on either side sends past a schema's bounds
local Failures = {
	queue = 64, -- The queue every event here keeps, the schema's default
	longReason = 200, -- Past the 128 bytes Example's Inventory.Transfer allows its reason
	outOfRange = 1000, -- Past the 999 a Stack's quantity allows
	notText = { 0xC3, 0x28 }, -- A two-byte sequence whose second byte does not continue it
}

-- A packet from a flat list of bytes
function Failures.packet(bytes: { number }): buffer
	local out: buffer = buffer.create(#bytes)
	for index: number, byte: number in bytes do
		buffer.writeu8(out, index - 1, byte)
	end
	return out
end

-- A list that keeps every failure a module reports
local function recorded(module: any): { Report }
	local reports: { Report } = {}

	module.onFailure(function (player: any, kind: string, detail: string)
		table.insert(reports, { player = player, kind = kind, detail = detail })
	end)

	return reports
end

function Failures.setup(name: string): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local player: any, transport: Transport = mock:join("Alice")
	local server: any = Generated.module("Server", MODULES[name].server, mock.server)
	local client: any = Generated.module("Client", MODULES[name].client, transport)
	local names: { [string]: boolean } = {}

	for _, side: any in { server, client } do
		for _, registry: any in { side.events, side.functions } do
			for key: string in registry do
				names[key] = true
			end
		end
	end

	return {
		mock = mock,
		player = player,
		transport = transport,
		server = server,
		client = client,
		names = names,
		failures = { server = recorded(server), client = recorded(client) },
	}
end

-- Enough steps for a server fire to wait out the client's handshake and arrive, or for a call to come back
function Failures.steps(mock: Mock)
	mock:step()
	mock:step()
	mock:step()
end

-- Runs one step on a thread of its own, so a listener that yields in it is resumed only after a frame has passed
function Failures.across(mock: Mock)
	local thread: thread = coroutine.create(function ()
		mock:step()
	end)

	coroutine.resume(thread)
	mock:step()
	coroutine.resume(thread)
end

-- A failure of a message names it once: the text before the first colon is its registry name, never twice over
function Failures.named(report: Report?, kind: string, name: string)
	local found: Report = assert(report, `no {kind} failure was reported`)

	expect(found.kind).is(kind)
	expect(found.detail:match("^(.-): ")).is(name)
	expect(found.detail:sub(1, 2 * #name + 4)).never_is(`{name}: {name}: `)
end

return Failures
