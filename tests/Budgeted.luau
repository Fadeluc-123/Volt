--[[
    What the tests of the per-player budget run over: a server and Alice's
    handshaken client over one mock, the Damage message they fire and hear,
    and the bytes written for a player and not yet sent
--]]

--!strict
local task = require("@lune/task")

local Generated = require("./Generated")
local Served = require("./Served")
local Volt = require("@volt")

type Mock = Volt.Mock
type Runtime = Volt.Runtime

export type Hit = { target: number, amount: number }

-- A server and Alice's handshaken client over one mock, each running its side's module
export type Harness = {
	mock: Mock,
	alice: any,
	server: any,
	client: any,
	runtime: Runtime,
	failures: { string },
}

local Budgeted = {
	belowEveryFrame = 1, -- A budget in bytes a second that any packet at all takes the count past
	damageBytes = 4, -- A Damage message's id, u16 and u8
}

function Budgeted.hit(target: number): Hit
	return { target = target, amount = 1 }
end

-- What a client's handshake takes: one step flushes it and the next reads it
function Budgeted.connected(name: string): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local server: any, failures: { string }, runtime: Runtime = Served.serve(name, mock)
	local alice: any, transport: Volt.Transport = mock:join("Alice")
	local client: any = Generated.module("Client", Served.modules[name].client, transport)

	mock:step()
	mock:step()

	return { mock = mock, alice = alice, server = server, client = client, runtime = runtime, failures = failures }
end

-- A list a Damage listener fills with each target, in the order heard
function Budgeted.hearing(harness: Harness): { number }
	local heard: { number } = {}

	harness.client.Damage.on(function (value: Hit)
		table.insert(heard, value.target)
	end)

	return heard
end

-- The bytes written for a player and not yet sent, those a budget holds back included
function Budgeted.pending(runtime: Runtime, player: any): number
	local _, written: number = runtime:traffic(player)
	return written
end

return Budgeted
