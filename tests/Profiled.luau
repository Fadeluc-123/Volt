--[[
    The harness the tooling tests share: a server and Alice's client over
    one mock, each running a schema's module, its shards answered by name,
    with a debug of its own whose profiler logs every label as the
    MicroProfiler's stack takes it, and every packet either side fires
    kept with its side array, as an inspector is handed it
--]]

--!strict
local task = require("@lune/task")

local Generated = require("./Generated")
local Volt = require("@volt")
local TargetsTypes = require("@volt/Compiler/Config/Types/Targets")

type Extra = TargetsTypes.Extra
type Mock = Volt.Mock
type Transport = Volt.Transport

-- Every label one side opened and closed, in order, and those still open, the innermost last
export type Labels = { log: { string }, open: { string } }

export type Kept = { packet: buffer, side: { any }? }

export type Harness = {
	mock: Mock,
	alice: any,
	transport: Transport, -- Alice's own, which a packet built by hand reaches the server through
	server: any,
	client: any,
	labels: { server: Labels, client: Labels },
	toServer: { Kept },
	toClient: { Kept },
}

-- A debug whose profiler keeps what is open as the MicroProfiler does, so a label closed twice or never shows
local function recording(labels: Labels): { [string]: any }
	return {
		profilebegin = function (label: string)
			table.insert(labels.open, label)
			table.insert(labels.log, label)
		end,

		profileend = function ()
			table.insert(labels.log, table.remove(labels.open) and "end" or "end of nothing")
		end,
	}
end

-- A transport that keeps each packet it fires, on either remote, before firing it on
local function kept(transport: Transport, into: { Kept }): Transport
	local copy: Transport = table.clone(transport)
	local reliable, unreliable = transport.reliable, transport.unreliable

	copy.reliable = function (target: any, packet: buffer, side: { any }?)
		table.insert(into, { packet = packet, side = side })
		reliable(target, packet, side)
	end

	copy.unreliable = function (target: any, packet: buffer, side: { any }?)
		table.insert(into, { packet = packet, side = side })
		unreliable(target, packet, side)
	end

	return copy
end

return function (name: string, text: string): Harness
	local clientText: string, serverText: string, _: string, extra: { Extra } = Generated.modules(name, text)
	local mock: Mock = Volt.mock(task.spawn)
	local alice: any, transport: Transport = mock:join("Alice")
	local shards: { [string]: string } = {}
	local labels: { server: Labels, client: Labels } =
		{ server = { log = {}, open = {} }, client = { log = {}, open = {} } }
	local toServer: { Kept }, toClient: { Kept } = {}, {}

	for _, file: Extra in extra do
		shards[`./{file.output:match("^(.-)%.luau$")}`] = file.text
	end

	-- Each side keeps what it fires through the transport it is started on, the server's every player's packets
	local serverGlobals: { [string]: any } = { debug = recording(labels.server) }
	local clientGlobals: { [string]: any } = { debug = recording(labels.client) }
	local server: any = Generated.module("Server", serverText, kept(mock.server, toClient), shards, serverGlobals)
	local client: any = Generated.module("Client", clientText, kept(transport, toServer), shards, clientGlobals)

	return {
		mock = mock,
		alice = alice,
		transport = transport,
		server = server,
		client = client,
		labels = labels,
		toServer = toServer,
		toClient = toClient,
	}
end
