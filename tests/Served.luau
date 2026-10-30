--[[
    What the tests of the player lifecycle, of reentry and of the budget
    run over: each schema's generated client and server compiled once,
    Broadcasts again with a frame capped at two Damage messages, a server
    module started over a mock with every failure kept, and the steps a
    held fire takes
--]]

--!strict
local fs = require("@lune/fs")

local Generated = require("./Generated")
local Volt = require("@volt")

type Mock = Volt.Mock
type Runtime = Volt.Runtime

type Modules = { client: string, server: string }

-- A reliable and an unreliable event the server fires, then the client's, then a reply, a channel and a dictionary
local SCHEMAS: { string } = { "Broadcasts", "Events", "Functions", "Streams", "Dictionary" }
local CAP: number = 8 -- Two Damage messages' bytes, so a third takes a player's frame past the cap

local Served = {
	modules = {} :: { [string]: Modules }, -- Each schema's, by its name, and the capped Broadcasts as Capped
}

for _, name: string in SCHEMAS do
	local client: string, server: string = Generated.modules(name, fs.readFile(`tests/Schemas/{name}.volt`))
	Served.modules[name] = { client = client, server = server }
end

local capped: string = `option maxOutgoing = {CAP}\n{fs.readFile("tests/Schemas/Broadcasts.volt")}`
local cappedClient: string, cappedServer: string = Generated.modules("Broadcasts", capped)

Served.modules.Capped = { client = cappedClient, server = cappedServer }

-- A server module over a mock with every failure it reports kept, then the runtime it started
function Served.serve(name: string, mock: Mock): (any, { string }, Runtime)
	local server: any, runtime: Runtime = Generated.module("Server", Served.modules[name].server, mock.server)
	local failures: { string } = {}

	server.onFailure(function (_, kind: string, detail: string)
		table.insert(failures, `{kind}: {detail}`)
	end)

	return server, failures, runtime
end

-- A server fire before a client's handshake waits for it: one step flushes the handshake, one reads it, one delivers
function Served.held(mock: Mock)
	mock:step()
	mock:step()
	mock:step()
end

return Served
