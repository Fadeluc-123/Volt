--[[
    Proves ordered unreliable events end to end, over the modules of
    Ordered.volt and the mock: each side's golden; a client's Aims carrying
    sequences 1, 2 and 3 and heard in order; the generated readers keeping
    a newer Aim and dropping a duplicate or an older one, across the wrap
    and on either side, with no failure; and fireAll giving every player
    and a bot their own next sequence
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local golden = require("./Expected")
local handshake = require("./Handshake")
local hex = require("./Hex")
local packet = require("./Packet")
local tapped = require("./Tapped")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Fired = tapped.Fired
type Mock = Volt.Mock
type Transport = Volt.Transport

type Report = { kind: string, detail: string } -- One failure a side reported

local SCHEMA: string = fs.readFile("tests/Schemas/Ordered.volt")
local CLIENT: string, SERVER: string, TYPES: string = Generated.modules("Ordered", SCHEMA)
local HASH: number = select(2, Generated.compile("Ordered", SCHEMA))
local SIDES: { { name: string, text: string } } =
	{ { name = "Client", text = CLIENT }, { name = "Server", text = SERVER }, { name = "Types", text = TYPES } }

local AIM: number = 1 -- Aim's id in both directions
local AIM_BYTES: number = 7 -- Its id, its sequence, then yaw and pitch as a u16 each

-- Raw yaws that read back as -3.2, -1.6, 0.0 and 3.2 to one place, so a listener says which message it heard
local LOW: number = 0
local OTHER: number = 16384
local MIDDLE: number = 32768
local HIGH: number = 65535

-- A list that keeps every failure a module reports
local function recorded(module: any): { Report }
	local reports: { Report } = {}

	module.onFailure(function (_, kind: string, detail: string)
		table.insert(reports, { kind = kind, detail = detail })
	end)

	return reports
end

-- One Aim as a sender writes it: the id, the sequence and the yaw little-endian, then a pitch of raw 0
local function aim(sequence: number, yaw: number): { number }
	return { AIM, sequence % 256, sequence // 256, yaw % 256, yaw // 256, 0, 0 }
end

-- Every message given as one packet's bytes
local function messages(...: { number }): buffer
	local bytes: { number } = {}

	for index: number = 1, select("#", ...) do
		local message: { number } = (select(index, ...))
		table.move(message, 1, #message, #bytes + 1, bytes)
	end

	return packet(bytes)
end

-- A listener that keeps the yaw of every Aim it hears to one place, on either side
local function listen(module: any, heard: { string })
	module.Aim.on(function (...: any)
		local count: number = select("#", ...)
		table.insert(heard, string.format("%.1f", (select(count - 1, ...))))
	end)
end

describe("Ordered", function ()
	for _, side in SIDES do
		test(`renders the {side.name:lower()} module as its golden file`, function ()
			expect(golden("tests/Golden/Ordered", side.name, side.text)).is(side.text)
		end)
	end

	describe("over the mock", function ()
		test("three Aims a client fires in one frame carry sequences 1, 2 and 3 and are heard in order", function ()
			local mock: Mock = Volt.mock(task.spawn)
			local _, transport: Transport = mock:join("Alice")
			local fired: { Fired } = {}
			local server: any = Generated.module("Server", SERVER, mock.server)
			local client: any = Generated.module("Client", CLIENT, tapped(transport, fired))
			local heard: { string } = {}

			listen(server, heard)

			client.Aim.fire(-3.2, 0)
			client.Aim.fire(0, 0)
			client.Aim.fire(3.2, 0)
			mock:step()
			mock:step()

			-- The handshake's packet, then the three Aims in one unreliable packet, each its id, sequence, yaw and pitch
			expect(`{fired[2].remote} {hex(fired[2].packet)}`).is(
				"U 01 01 00 00 00 00 80 01 02 00 00 80 00 80 01 03 00 FF FF 00 80"
			)
			expect(table.concat(heard, ",")).is("-3.2,0.0,3.2")
		end)

		test(
			"the server keeps each newer Aim and drops a duplicate or an older one across the wrap, all counted in",
			function ()
				local mock: Mock = Volt.mock(task.spawn)
				local alice: any, transport: Transport = mock:join("Alice")
				local server: any = Generated.module("Server", SERVER, mock.server)
				local failures: { Report } = recorded(server)
				local heard: { string } = {}

				listen(server, heard)

				-- 65535 first, 0 after it as newer, 0 again, 65535 after 0 as older, 5 newer, 4 older
				transport.reliable(nil, handshake(HASH))
				transport.unreliable(
					nil,
					messages(
						aim(65535, LOW),
						aim(0, MIDDLE),
						aim(0, OTHER),
						aim(65535, OTHER),
						aim(5, HIGH),
						aim(4, OTHER)
					)
				)
				mock:step()

				expect(table.concat(heard, ",")).is("-3.2,0.0,3.2")
				expect(server.stats(alice).messagesIn).is(6)
				expect(#failures).is(0)
			end
		)

		test("an older server packet is dropped on the client, counted in, with no failure", function ()
			local mock: Mock = Volt.mock(task.spawn)
			local alice: any, transport: Transport = mock:join("Alice")
			local client: any = Generated.module("Client", CLIENT, transport)
			local failures: { Report } = recorded(client)
			local heard: { string } = {}

			listen(client, heard)

			-- Built by hand, since the server's own writer never sends one older than the last
			mock.server.unreliable(alice, messages(aim(2, HIGH)))
			mock.server.unreliable(alice, messages(aim(1, LOW)))
			mock:step()

			expect(table.concat(heard, ",")).is("3.2")
			expect(client.stats().messagesIn).is(2)
			expect(#failures).is(0)
		end)

		test("fireAll gives each player and a bot their own next sequence, read from the bytes sent to each", function ()
			local mock: Mock = Volt.mock(task.spawn)
			local fired: { Fired } = {}
			local server: any = Generated.module("Server", SERVER, tapped(mock.server, fired))
			local alice: any, aliceSide: Transport = mock:join("Alice")
			local _, bobSide: Transport = mock:join("Bob")
			local sequences: { [string]: { number } } = { Alice = {}, Bob = {}, Helper = {} }

			mock:addBot("Helper")

			-- A held player's unreliable messages are dropped, so both handshake first; a bot is never held
			aliceSide.reliable(nil, handshake(HASH))
			bobSide.reliable(nil, handshake(HASH))
			mock:step()

			-- Alice is fired at alone first, so a count shared between targets would show
			server.Aim.fire(alice, 0, 0)
			server.Aim.fireAll(0, 0)
			server.Aim.fireAll(0, 0)
			mock:step()

			for _, entry: Fired in fired do
				for offset: number = 0, buffer.len(entry.packet) - 1, AIM_BYTES do
					table.insert(sequences[entry.target.Name], buffer.readu16(entry.packet, offset + 1))
				end
			end

			local lines: { string } = {}
			for _, name: string in { "Alice", "Bob", "Helper" } do
				table.insert(lines, `{name} {table.concat(sequences[name], ",")}`)
			end

			expect(table.concat(lines, ", ")).is("Alice 1,2,3, Bob 1,2, Helper 1,2")
		end)
	end)
end)
