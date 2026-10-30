--[[
    Proves an ordered event's sequence: each send state counts each event
    on its own from 1 and wraps after 65535, a broadcast writes every
    target its own next one, and the receiver keeps a newer message and
    drops a duplicate or an older one, which still spends the event's rate
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local handshake = require("./Handshake")
local packet = require("./Packet")
local Volt = require("@volt")
local Limits = require("@volt/Limits")
local Send = require("@volt/Send")
local Types = require("@volt/Config/Types/Runtime")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock
type Reader = Types.Reader
type Runtime = Volt.Runtime
type Send = Send.Send
type State = Send.State
type Transport = Volt.Transport

type Report = { kind: string, detail: string } -- One failure a runtime reported

local AIM: number = 1 -- The one ordered event's id, in either direction
local SEQUENCE: number = 1 -- Where its sequence sits in the message, after the one-byte id
local MAX_OUTGOING: number = 256

-- The options the runtime reads, at the compiler's defaults
local OPTIONS: { [string]: any } = {
	flush = 1,
	manualReplication = false,
	maxPacket = 8192,
	maxPacketsPerSecond = 240,
	maxOutgoing = 262144,
	unreliableBudget = 900,
}

-- A send that keeps what it fires to nobody, for its states alone
local function quiet(): Send
	local function nothing() end

	return Send.new(nothing, Limits.fresh(), nothing, MAX_OUTGOING, 900)
end

-- Aim's bytes as its writer leaves them: the id, the sequence after it, then one byte of value, marked
local function writeAim(send: Send, value: number)
	local offset: number, out: buffer = send.begin(4)

	buffer.writeu8(out, offset, AIM)
	buffer.writeu16(out, offset + SEQUENCE, send.order(AIM))
	buffer.writeu8(out, offset + 3, value)
	send.mark()
end

-- The sequence of each Aim a state holds, in order
local function sequences(state: State): string
	local list: { number } = {}

	for offset: number = 0, state.cursor - 1, 4 do
		table.insert(list, buffer.readu16(state.out, offset + SEQUENCE))
	end

	return table.concat(list, ",")
end

--[[
    A runtime on one side of a mock with one ordered event, whose reader
    takes the sequence and a byte of value and ends in ordered, with a
    rate when given, every failure recorded and the values heard listed
--]]

local function setup(side: string, rate: number?): (Runtime, Mock, { string }, { Report })
	local mock: Mock = Volt.mock(task.spawn)
	local seen: { string } = {}
	local failures: { Report } = {}
	local runtime: Runtime

	local function read(from: any, bytes: buffer, cursor: number, _: { any }, sideCursor: number, _: number)
		local sequence: number = buffer.readu16(bytes, cursor)
		return runtime:ordered(AIM, sequence, from, cursor + 3, sideCursor, buffer.readu8(bytes, cursor + 2))
	end

	local reader: Reader = read
	local transport: Transport = mock.server

	if side == "client" then
		local _, client: Transport = mock:join("Alice")
		transport = client
	end

	runtime = Volt.start({
		version = Volt.version,
		hash = 0,
		scope = "Test",
		side = side,
		idBytes = 1,
		options = OPTIONS,
		messages = {
			[AIM] = { name = "Aim", kind = "event", mode = "ManySync", queue = 4, rate = rate, read = reader },
		},
		outgoing = {},
	}, transport)

	runtime:onFailure(function (_, kind: string, detail: string)
		table.insert(failures, { kind = kind, detail = detail })
	end)

	runtime:on(AIM, function (...: any)
		table.insert(seen, tostring((select(select("#", ...), ...))))
	end)

	return runtime, mock, seen, failures
end

-- One Aim message from a sender, its sequence's two bytes little-endian, then its value
local function aim(sequence: number, value: number): { number }
	return { AIM, sequence % 256, sequence // 256, value }
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

describe("Sequences", function ()
	describe("on the send", function ()
		test("each state counts each ordered event on its own, from 1", function ()
			local send: Send = quiet()
			local a: State, b: State = send:add("a", Limits.fresh()), send:add("b", Limits.fresh())
			local other: number = AIM + 1

			send.current = a

			local counted: { number } = { send.order(AIM), send.order(AIM), send.order(other) }

			send.current = b
			table.insert(counted, send.order(AIM))

			expect(table.concat(counted, ",")).is("1,2,1,1")
		end)

		test("wraps from 65535 to 0 and steps on to 1", function ()
			local send: Send = quiet()
			local state: State = send:add("a", Limits.fresh())

			send.current = state
			state.sequences = { [AIM] = 65534 }

			expect(`{send.order(AIM)},{send.order(AIM)},{send.order(AIM)}`).is("65535,0,1")
		end)

		test("a broadcast writes each target its own next sequence over the scratch one", function ()
			local send: Send = quiet()
			local a: State, b: State, c: State =
				send:add("a", Limits.fresh()), send:add("b", Limits.fresh()), send:add("c", Limits.fresh())

			-- A had one sent to it alone before, so its count is one ahead
			send.current = a
			writeAim(send, 1)

			send.current = send.scratch
			writeAim(send, 2)
			send:broadcast(nil, nil, AIM, SEQUENCE)

			writeAim(send, 3)
			send:broadcast({ "c" }, nil, AIM, SEQUENCE)

			expect(`{sequences(a)} {sequences(b)} {sequences(c)}`).is("1,2 1 1,2")
		end)

		test("fireAll and fireList through the runtime give each player their own count", function ()
			local mock: Mock = Volt.mock(task.spawn)
			local alice: any, aliceSide: Transport = mock:join("Alice")
			local bob: any, bobSide: Transport = mock:join("Bob")
			local heard: { [string]: { number } } = { Alice = {}, Bob = {} }

			local runtime: Runtime = Volt.start({
				version = Volt.version,
				hash = 0,
				scope = "Test",
				side = "server",
				idBytes = 1,
				options = OPTIONS,
				messages = {},
				outgoing = {
					[AIM] = {
						name = "Aim",
						kind = "event",
						reliable = false,
						sequence = SEQUENCE,
						minBytes = 4,
						maxBytes = 4,
					},
				},
			}, mock.server)

			-- What each player's client is sent: the sequence of every Aim in every packet
			for player: any, side: Transport in { [alice] = aliceSide, [bob] = bobSide } do
				side.receive(function (_, bytes: buffer)
					for offset: number = 0, buffer.len(bytes) - 1, 4 do
						table.insert(heard[player.Name], buffer.readu16(bytes, offset + SEQUENCE))
					end
				end)

				side.reliable(nil, handshake(0))
			end

			mock:step()

			local function write(value: number)
				writeAim(runtime.unreliable, value)
			end

			runtime:broadcast(AIM, nil, nil, write, 1)
			runtime:broadcast(AIM, { bob }, nil, write, 2)
			runtime:broadcast(AIM, nil, nil, write, 3)

			mock:step()
			mock:step()

			expect(`{table.concat(heard.Alice, ",")} {table.concat(heard.Bob, ",")}`).is("1,2 1,2,3")
		end)
	end)

	describe("on the receive", function ()
		test("keeps a newer message and drops an older one, both counted in, with no failure", function ()
			local runtime: Runtime, mock: Mock, seen: { string }, failures: { Report } = setup("client")

			mock.server.unreliable(mock.players[1], messages(aim(5, 50), aim(4, 40)))
			mock:step()

			expect(table.concat(seen, ",")).is("50")
			expect(runtime:stats().messagesIn).is(2)
			expect(#failures).is(0)
		end)

		test("hears a duplicate once", function ()
			local _, mock: Mock, seen: { string } = setup("client")

			mock.server.unreliable(mock.players[1], messages(aim(7, 1)))
			mock.server.unreliable(mock.players[1], messages(aim(7, 2)))
			mock:step()

			expect(table.concat(seen, ",")).is("1")
		end)

		test("takes 0 after 65535 as newer and 65535 after 1 as older, keeping each sender's own", function ()
			local _, mock: Mock, seen: { string } = setup("server")
			local sides: { Transport } = {}

			for _, name: string in { "Alice", "Bob", "Carol" } do
				local _, side: Transport = mock:join(name)

				side.reliable(nil, handshake(0))
				table.insert(sides, side)
			end

			-- Bob's first would be older than Alice's last were one count kept for everyone
			sides[1].unreliable(nil, messages(aim(65535, 1), aim(0, 2)))
			sides[2].unreliable(nil, messages(aim(65535, 3), aim(1, 4)))
			sides[3].unreliable(nil, messages(aim(1, 5), aim(65535, 6)))
			mock:step()

			expect(table.concat(seen, ",")).is("1,2,3,4,5")
		end)

		test("a stale message spends the event's rate, so the next newer one is past it", function ()
			local _, mock: Mock, seen: { string }, failures: { Report } = setup("server", 2)
			local _, client: Transport = mock:join("Alice")

			client.reliable(nil, handshake(0))
			client.unreliable(nil, messages(aim(1, 1), aim(1, 2), aim(2, 3)))
			mock:step()

			expect(table.concat(seen, ",")).is("1")
			expect(#failures).is(1)
			expect(`{failures[1].kind}: {failures[1].detail}`).is("rate: Aim: over 2 a second")
		end)
	end)
end)
