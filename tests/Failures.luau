--[[
    The harness both failure suites share: the modules of every schema
    they raise failures over, compiled unchecked, a server and one client
    over a mock with every failure each side reports kept in order, a
    packet from a list of bytes, and the steps a fire or a call takes
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Generated = require("./Generated")
local Volt = require("@volt")

type Mock = Volt.Mock
type Transport = Volt.Transport

export type Report = { kind: string, detail: string } -- One failure a side reported

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
local SCHEMAS: { string } = { "Events", "Functions", "Exports", "Records", "Example" }

local MODULES: { [string]: { client: string, server: string } } = {}

for _, name: string in SCHEMAS do
	local source: string = `option writeValidation = false\n{fs.readFile(`tests/Schemas/{name}.volt`)}`
	local client: string, server: string = Generated.modules(name, source)

	MODULES[name] = { client = client, server = server }
end

local Failures = {}

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

	module.onFailure(function (_, kind: string, detail: string)
		table.insert(reports, { kind = kind, detail = detail })
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

return Failures
