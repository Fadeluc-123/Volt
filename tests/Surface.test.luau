--[[
    Proves the surface a package is written against, over the modules of
    Surface.volt in every casing: each handle's exact members on each side,
    the module's own members, everything frozen, the registry handing back
    the nested handles, rate on either side, onFailure by casing, version
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local Volt = require("@volt")
local Types = require("@volt/Compiler/Targets/Types")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock

-- A server and one client over one mock, each running the module of its side
type Harness = { mock: Mock, server: any, client: any }

local SURFACE: string = fs.readFile("tests/Schemas/Surface.volt")
local CASINGS: { string } = { "camel", "pascal", "snake" }
local FROMS: { string } = { "Client", "Server", "Both" }
local MODES: { string } = { "SingleSync", "SingleAsync", "ManySync", "ManyAsync", "Polling" }
local BROADCASTS: { string } = { "fire", "fireAll", "fireList", "fireExcept", "fireSet" }

-- The members every module has of its own, then those the server alone has, in camel
local OWN: { string } = { "version", "hooks", "rate", "flush", "onFailure", "stats", "events", "functions", "exports" }
local SERVER_OWN: { string } = { "onJoin", "onLeave", "onHandshake", "traffic", "budget", "isBot" }

-- The members an event's handle has on one side, in camel: a fire when the side sends it, on and iter when it hears it
local function members(server: boolean, from: string, mode: string): { string }
	local list: { string } = {}
	local fires: boolean = from == "Both" or (from == "Server") == server
	local hears: boolean = from == "Both" or (from == "Server") ~= server

	if fires then
		local fired: { string } = server and BROADCASTS or { "fire" }
		table.move(fired, 1, #fired, 1, list)
	end

	if hears and mode ~= "Polling" then
		table.insert(list, "on")
	end

	if hears then
		table.insert(list, "iter")
	end

	return list
end

-- A table's keys, sorted, as one line
local function keys(value: { [string]: any }): string
	local list: { string } = {}
	for key: string in value do
		table.insert(list, key)
	end

	table.sort(list)
	return table.concat(list, " ")
end

-- Names in a casing, sorted, as one line, which is what keys reads back
local function cased(names: { string }, casing: string): string
	local list: { string } = {}
	for _, name: string in names do
		table.insert(list, Types.cased(name, casing))
	end

	table.sort(list)
	return table.concat(list, " ")
end

local function setup(text: string): Harness
	local client: string, server: string = Generated.modules("Surface", text)
	local mock: Mock = Volt.mock(task.spawn)
	local _, transport = mock:join("Alice")

	return {
		mock = mock,
		server = (Generated.module("Server", server, mock.server)),
		client = (Generated.module("Client", client, transport)),
	}
end

describe("Surface", function ()
	for _, casing: string in CASINGS do
		describe(casing, function ()
			local text: string = `option casing = {casing}\n{SURFACE}`
			local harness: Harness = setup(text)
			local sides: { { server: boolean, module: any } } = {
				{
					server = true,
					module = harness.server,
				},
				{
					server = false,
					module = harness.client,
				},
			}

			test("every handle has exactly the members its side sends and hears it by", function ()
				for _, side in sides do
					for _, from: string in FROMS do
						for _, mode: string in MODES do
							local handle: { [string]: any } = side.module[`{from}{mode}`]
							expect(keys(handle)).is(cased(members(side.server, from, mode), casing))
						end
					end

					expect(keys(side.module.Ns.Ask)).is(cased({ side.server and "on" or "invoke" }, casing))
					expect(keys(side.module.Ns.Tell)).is(
						cased(side.server and { "invoke" } or { "on", "connected" }, casing)
					)
				end
			end)

			test("the module holds its entries and its own members, the player ones on the server alone", function ()
				for _, side in sides do
					local names: { string } = { "Ns" }

					for _, from: string in FROMS do
						for _, mode: string in MODES do
							table.insert(names, `{from}{mode}`)
						end
					end

					for _, name: string in OWN do
						table.insert(names, Types.cased(name, casing))
					end

					local only: { string } = side.server and SERVER_OWN or {}
					for _, name: string in only do
						table.insert(names, Types.cased(name, casing))
					end

					table.sort(names)
					expect(keys(side.module)).is(table.concat(names, " "))
				end
			end)

			test("the module, its namespace, every handle and every map are frozen", function ()
				for _, side in sides do
					local module: any = side.module

					expect(table.isfrozen(module)).is(true)
					expect(table.isfrozen(module.Ns)).is(true)
					expect(table.isfrozen(module.Ns.Ask)).is(true)
					expect(table.isfrozen(module.Ns.Tell)).is(true)

					for _, map: string in { "events", "functions", "exports" } do
						expect(table.isfrozen(module[Types.cased(map, casing)])).is(true)
					end

					for _, from: string in FROMS do
						for _, mode: string in MODES do
							expect(table.isfrozen(module[`{from}{mode}`])).is(true)
						end
					end
				end
			end)

			test(
				"the registry hands back the nested handle, nil for a missing name, and an empty map frozen",
				function ()
					for _, side in sides do
						local module: any = side.module
						local events: { [string]: any } = module[Types.cased("events", casing)]
						local functions: { [string]: any } = module[Types.cased("functions", casing)]
						local exports: { [string]: any } = module[Types.cased("exports", casing)]

						expect(events.BothPolling).is(module.BothPolling)
						expect(functions["Ns.Ask"]).is(module.Ns.Ask)
						expect(functions["Ns.Tell"]).is(module.Ns.Tell)
						expect(events.Nope).is(nil)
						expect((next(exports))).is(nil)
					end
				end
			)

			test("version is the runtime's on both sides", function ()
				expect(harness.server[Types.cased("version", casing)]).is(Volt.version)
				expect(harness.client[Types.cased("version", casing)]).is(Volt.version)
			end)

			test("onFailure is a function under that name in camel alone, on both sides", function ()
				for _, side in sides do
					expect(type(side.module.onFailure) == "function").is(casing == "camel")
					expect(type(side.module[Types.cased("onFailure", casing)])).is("function")
				end
			end)
		end)
	end

	test("a snake schema may declare a top-level onFailure, which V4001 refuses only cased", function ()
		local declaration: string = "event onFailure { from: Client, type: Reliable, call: SingleSync }"
		local harness: Harness = setup(`option casing = snake\n{SURFACE}\n{declaration}`)

		for _, module: any in { harness.server, harness.client } do
			expect(type(module.onFailure)).is("table")
			expect(type(module.on_failure)).is("function")
		end
	end)

	describe("rate", function ()
		test("on the server lets one of two messages in one frame through, and reports the other", function ()
			local harness: Harness = setup(SURFACE)
			local heard: number = 0
			local failures: { string } = {}

			harness.server.onFailure(function (_, kind: string)
				table.insert(failures, kind)
			end)
			harness.server.ClientSingleSync.on(function ()
				heard += 1
			end)

			harness.server.rate("ClientSingleSync", 1)
			harness.client.ClientSingleSync.fire()
			harness.client.ClientSingleSync.fire()
			harness.mock:step()
			harness.mock:step()

			expect(heard).is(1)
			expect(table.concat(failures, " ")).is("rate")
		end)

		test("on the server refuses a name it does not hear: unknown, send-only, or a function it calls", function ()
			local harness: Harness = setup(SURFACE)

			expect((pcall(harness.server.rate, "Nope", 1))).is(false)
			expect((pcall(harness.server.rate, "ServerSingleSync", 1))).is(false)
			expect((pcall(harness.server.rate, "Ns.Tell", 1))).is(false)
		end)

		test("on the client returns without effect", function ()
			local harness: Harness = setup(SURFACE)

			expect((pcall(harness.client.rate, "Nope", 1))).is(true)
		end)
	end)

	test("the server's player members reach its runtime", function ()
		local harness: Harness = setup(SURFACE)
		local bot = harness.mock:addBot("Bot")
		local joined: { string } = {}
		local handshaken: number = 0

		local disconnect: () -> () = harness.server.onJoin(function (player: any)
			table.insert(joined, player.Name)
		end)
		harness.server.onHandshake(function ()
			handshaken += 1
		end)

		-- The client's handshake goes at its first Heartbeat and is read at the step after
		harness.mock:step()
		harness.mock:step()
		disconnect()

		local sent: number, pending: number = harness.server.traffic(harness.mock.players[1])

		-- Everyone already set up is replayed, in no order the runtime promises
		table.sort(joined)

		expect(table.concat(joined, " ")).is("Alice Bot")
		expect(handshaken).is(1)
		expect(harness.server.isBot(bot)).is(true)
		expect(harness.server.isBot(harness.mock.players[1])).is(false)
		expect(type(sent) == "number" and type(pending) == "number").is(true)
	end)
end)
