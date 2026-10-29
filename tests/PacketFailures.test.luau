--[[
    Proves the failure detail contract for a failure of a whole packet,
    over the generated modules on the server and on the client: a packet
    before the handshake, an unknown id, a wrong hash, the packet rate,
    the outgoing cap, a call it drops and a departed player name no message
--]]

--!strict
local Suite = require("./Suite")
local Failures = require("./Failures")
local handshake = require("./Handshake")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect
local packet = Failures.packet
local setup = Failures.setup
local steps = Failures.steps

type Harness = Failures.Harness
type Report = Failures.Report

local MAX_PACKETS: number = 240 -- The packets a player may send a second, the schema's default
local MAX_PACKET: number = 8192 -- What a client's reliable frame is capped at, the schema's default
local MAX_OUTGOING: number = 262144 -- What a player's frame, and so their hold, is capped at, the schema's default
local SYNC_BYTES: number = 2 -- Sync's id and its u8, as the server fires it
local TRANSFER_BYTES: number = 7 -- An Inventory.Transfer call's id, slot, two u8s and a u16
local WRONG_HASH: number = 0xBAD
local UNKNOWN_ID: number = 255 -- An id no schema here gives a message
local READY: number = 3 -- Ready's id on the server, which a raw packet before the handshake opens with
local PAST_RATE: number = 5 -- Packets past the rate in one step

-- Every failure of a kind names no message, so nothing routes it to a message's owner
local function unnamed(harness: Harness, reports: { Report }, kind: string)
	local count: number = 0

	for _, report: Report in reports do
		if report.kind == kind then
			count += 1
			expect(harness.names).never_has_key(report.detail:match("^(.-): ") or report.detail)
		end
	end

	expect(count > 0).is(true)
end

describe("Failures", function ()
	describe("on the server", function ()
		test(
			"a packet before the handshake, an unknown id, a wrong hash, the packet rate, the cap and departed name none",
			function ()
				local early: Harness = setup("Events")
				local wrong: Harness = setup("Events")
				local harness: Harness = setup("Events")
				local slow: any = harness.mock:join("Slow") -- No client, so what is fired at them is held step after step
				local half: number = MAX_OUTGOING // (2 * SYNC_BYTES)

				early.transport.reliable(nil, packet({ READY }))
				wrong.transport.reliable(nil, handshake(WRONG_HASH))
				steps(early.mock)
				steps(wrong.mock)
				wrong.server.Sync.fire(wrong.player, 1)

				-- Past the cap in one frame for a player who has handshaken, and over three for one held from the start
				for _ = 1, 2 * half + 1 do
					early.server.Sync.fire(early.player, 1)
				end
				for _ = 1, half do
					harness.server.Sync.fire(slow, 1)
				end

				early.mock:step()
				harness.mock:step()
				harness.transport.reliable(nil, packet({ UNKNOWN_ID }))
				harness.mock:step()

				for _ = 1, MAX_PACKETS + PAST_RATE do
					harness.transport.reliable(nil, buffer.create(0))
				end
				for _ = 1, half + 1 do
					harness.server.Sync.fire(slow, 1)
				end

				harness.mock:step()
				harness.mock:leave(harness.player)
				harness.server.Sync.fire(harness.player, 1)

				expect(early.failures.server[1].detail).is("before the handshake")
				expect(harness.failures.server[1].detail).is(`unknown message {UNKNOWN_ID}`)
				unnamed(early, early.failures.server, "packet")
				unnamed(harness, harness.failures.server, "packet")
				unnamed(wrong, wrong.failures.server, "handshake")
				unnamed(harness, harness.failures.server, "rate")
				unnamed(early, early.failures.server, "outgoing")
				unnamed(harness, harness.failures.server, "outgoing")
				unnamed(wrong, wrong.failures.server, "departed")
				unnamed(harness, harness.failures.server, "departed")
			end
		)
	end)

	describe("on the client", function ()
		test("an unknown id and a reliable frame past maxPacket, from a fire or at a call, name no message", function ()
			local harness: Harness = setup("Events")
			local functions: Harness = setup("Functions")
			local last: any = nil

			harness.mock.server.reliable(harness.player, packet({ UNKNOWN_ID }))

			for _ = 1, MAX_PACKET // 2 do
				harness.client.Sync.fire(1)
			end

			-- The handshake and every transfer but the last take 8188 bytes; the last would bring the frame to 8195
			for _ = 1, MAX_PACKET // TRANSFER_BYTES do
				last = functions.client.Inventory.Transfer.invoke(1, 2, 3)
			end

			expect(`{last.settled[1]} {last.settled[2]}`).is("false dropped")
			expect(#functions.failures.client).is(1)

			steps(harness.mock)

			unnamed(harness, harness.failures.client, "packet")
			unnamed(harness, harness.failures.client, "outgoing")
			unnamed(functions, functions.failures.client, "outgoing")
			expect(harness.failures.client[1].detail).is("over maxPacket, a message was dropped")
			expect(functions.failures.client[1].detail).is("over maxPacket, a message was dropped")
		end)
	end)
end)
