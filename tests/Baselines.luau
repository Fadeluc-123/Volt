--[[
    What the tests of the @delta baselines run over: a server and its
    players' clients on a mock, a writer and a reader of one @delta event
    written by hand as generated ones would be, and a plain event of five
    bytes that fills a frame
--]]

--!strict
local task = require("@lune/task")

local Volt = require("@volt")

type Mock = Volt.Mock
type Runtime = Volt.Runtime
type Schema = Volt.Schema
type Transport = Volt.Transport

export type Vitals = { health: number, stamina: number, gear: { level: number } }
export type Report = { player: any, kind: string, detail: string, kept: boolean } -- Whether the player still had baselines

-- A client runtime with every value its listeners heard, "ping" for the plain event, and what it reported
export type Client = { runtime: Runtime, heard: { any }, failures: { Report } }

-- A server and its players' clients over one mock, with every mask the server's writer was handed
export type Harness = {
	mock: Mock,
	server: Runtime,
	players: { any },
	clients: { [any]: Client },
	masks: { number },
	failures: { Report },
	write: (mask: number, value: any) -> (),
}

local FIELDS: { string } = { "health", "stamina", "gear" } -- Field i's bit is 2^(i - 1), and every field one byte

-- The options the runtime reads, at the compiler's defaults
local OPTIONS: { [string]: any } = {
	flush = 1,
	manualReplication = false,
	maxPacket = 8192,
	maxPacketsPerSecond = 240,
	maxOutgoing = 262144,
	unreliableBudget = 900,
}

local Baselines = {
	vitals = 1, -- The @delta event's id toward the client
	plain = 2, -- The plain event's id toward the client, with four bytes after it
	options = OPTIONS,
}

function Baselines.make(health: number, stamina: number, level: number): Vitals
	return { health = health, stamina = stamina, gear = { level = level } }
end

-- A schema table on one side, with the options and the rows given
function Baselines.schema(
	side: string,
	options: { [string]: any },
	rows: { [number]: any },
	streams: { string }?
): Schema
	return {
		version = Volt.version,
		hash = 0,
		scope = "Test",
		side = side,
		idBytes = 1,
		streams = streams,
		options = options,
		messages = side == "client" and rows or {},
		outgoing = side == "server" and rows or {},
	}
end

-- What a client heard, a line each: a value's three fields, or the plain event
function Baselines.lines(client: Client): string
	local list: { string } = {}

	for _, value: any in client.heard do
		table.insert(list, type(value) == "string" and value or `{value.health} {value.stamina} {value.gear.level}`)
	end

	return table.concat(list, ",")
end

-- A client on a transport whose reader reads each field the mask names and hands the rest to merge
function Baselines.client(transport: Transport): Client
	local heard: { any } = {}
	local failures: { Report } = {}
	local runtime: Runtime

	local function readVitals(_: any, from: buffer, cursor: number, _: { any }, sideCursor: number, _: number)
		local mask: number = buffer.readu8(from, cursor)
		local partial: { [string]: any } = {}

		cursor += 1

		for index: number, field: string in FIELDS do
			if bit32.btest(mask, 2 ^ (index - 1)) then
				local byte: number = buffer.readu8(from, cursor)

				partial[field] = field == "gear" and { level = byte } or byte
				cursor += 1
			end
		end

		return runtime:deliver(
			Baselines.vitals,
			nil,
			cursor,
			sideCursor,
			runtime:merge(Baselines.vitals, mask, partial)
		)
	end

	local function readPlain(_: any, _: buffer, cursor: number, _: { any }, sideCursor: number, _: number)
		return runtime:deliver(Baselines.plain, nil, cursor + 4, sideCursor)
	end

	runtime = Volt.start(
		Baselines.schema("client", OPTIONS, {
			[Baselines.vitals] = {
				name = "vitals",
				kind = "event",
				mode = "ManySync",
				queue = 64,
				fields = FIELDS,
				read = readVitals,
			},
			[Baselines.plain] = { name = "Ping", kind = "event", mode = "ManySync", queue = 64, read = readPlain },
		}),
		transport
	)

	runtime:onFailure(function (player: any, kind: string, detail: string)
		table.insert(failures, { player = player, kind = kind, detail = detail, kept = false })
	end)

	runtime:on(Baselines.vitals, function (value: Vitals)
		table.insert(heard, value)
	end)

	runtime:on(Baselines.plain, function ()
		table.insert(heard, "ping")
	end)

	return { runtime = runtime, heard = heard, failures = failures }
end

--[[
    A server over a mock with the players named, each with a client whose
    handshake has been read. Its writer checks a field before writing it
    unless the module's writers do not, when a wrong value raises in the
    buffer write instead
--]]

function Baselines.setup(names: { string }, options: { [string]: any }?): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local settings: { [string]: any } = table.clone(OPTIONS)
	local masks: { number } = {}
	local failures: { Report } = {}
	local players: { any } = {}
	local clients: { [any]: Client } = {}
	local server: Runtime

	for key: string, value: any in options or {} do
		settings[key] = value
	end

	local function writeVitals(mask: number, value: any)
		local offset: number, out: buffer = server.reliable.begin(2 + #FIELDS)

		buffer.writeu8(out, offset, Baselines.vitals)
		buffer.writeu8(out, offset + 1, mask)
		offset += 2

		for index: number, field: string in FIELDS do
			if bit32.btest(mask, 2 ^ (index - 1)) then
				local inner: any = value[field]

				if settings.writeValidation ~= false and field ~= "gear" and type(inner) ~= "number" then
					server.reliable.refuse(`vitals.{field}: expected u8`)
				end

				buffer.writeu8(out, offset, field == "gear" and inner.level or inner)
				offset += 1
			end
		end

		server.reliable.trim(offset)
		table.insert(masks, mask)
	end

	server = Volt.start(
		Baselines.schema("server", settings, {
			[Baselines.vitals] = {
				name = "vitals",
				kind = "event",
				reliable = true,
				fields = FIELDS,
				minBytes = 2,
				maxBytes = 5,
			},
			[Baselines.plain] = { name = "Ping", kind = "event", reliable = true, minBytes = 5, maxBytes = 5 },
		}),
		mock.server
	)

	server:onFailure(function (player: any, kind: string, detail: string)
		local state: any = (server :: any)._players[player]
		local kept: boolean = state ~= nil and state.sent ~= nil

		table.insert(failures, { player = player, kind = kind, detail = detail, kept = kept })
	end)

	for _, name: string in names do
		local player: any, transport: Transport = mock:join(name)

		table.insert(players, player)
		clients[player] = Baselines.client(transport)
	end

	mock:step()
	mock:step()

	return {
		mock = mock,
		server = server,
		players = players,
		clients = clients,
		masks = masks,
		failures = failures,
		write = writeVitals,
	}
end

-- Steps until what the server wrote this frame has been heard
function Baselines.round(harness: Harness)
	harness.mock:step()
	harness.mock:step()
end

-- The masks the writer was handed, sorted, since recipients on different masks are written in no set order
function Baselines.sorted(masks: { number }): string
	local copy: { number } = table.clone(masks)

	table.sort(copy)

	return table.concat(copy, ",")
end

-- A plain message of five bytes at one player, which fills their frame
function Baselines.fill(harness: Harness, player: any)
	harness.server:target(player)

	local offset: number, out: buffer = harness.server.reliable.begin(5)

	buffer.writeu8(out, offset, Baselines.plain)
	buffer.writeu32(out, offset + 1, 0)
end

return Baselines
