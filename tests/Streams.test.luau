--[[
    Proves channels end to end, over the modules of Streams.volt and the
    mock: each side's golden; Chat on byte 1 of the Reliable remote behind
    the handshake, and heard once that is read; each server packet opening
    with its byte and the stamp; each stream held for a late player in its
    own order; a handler's fires before its reply; a channel's cap, one
    packet rate for every stream, an unchecked fire, and the hooks and rate
    on a channel's event
--]]

--!strict
local Suite = require("./Suite")
local golden = require("./Expected")
local handshake = require("./Handshake")
local hex = require("./Hex")
local Streamed = require("./Streamed")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect
local compiled = Streamed.compiled
local connected = Streamed.connected
local into = Streamed.into
local lines = Streamed.lines
local serve = Streamed.serve
local start = Streamed.start
local steps = Streamed.steps

type Box = Streamed.Box
type Harness = Streamed.Harness
type Report = Streamed.Report

local STAMP: number = 1761700000.25 -- The server time of the design's worked example
local STAMP_HEX: string = "00 00 10 28 5A 40 DA 41" -- That time as the f64 a server packet opens with after its byte
local LONG: string = string.rep("x", 150) -- A Chat of 152 bytes, so two pass the capped client's channel frame
local CAPPED_PACKET: number = 208 -- The least maxPacket V3012 allows here: the longest Chat, the handshake and the byte
local PACKETS: number = 3 -- The packet rate of the limited modules

-- Answers every Ask with one more than it was given
local function answer(server: any)
	server.Ask.on(function (_, value: number): number
		return value + 1
	end)
end

-- Keeps every Chat the server hears
local function chats(server: any): { string }
	local heard: { string } = {}

	server.Chat.on(function (_, text: string)
		table.insert(heard, text)
	end)

	return heard
end

describe("Streams", function ()
	for _, side in Streamed.sides do
		test(`renders the {side.name:lower()} module as its golden file`, function ()
			expect(golden("tests/Golden/Streams", side.name, side.text)).is(side.text)
		end)
	end

	describe("over the mock", function ()
		test("a Chat fired in the client's first frame follows its handshake and is heard once that is read", function ()
			local harness: Harness = start(serve())
			local heard: { string } = chats(harness.server)

			harness.client.Chat.fire("hi")
			steps(harness, 2)

			-- Byte 0 and the handshake, then byte 1 and Chat: its id, its length and "hi", both on the Reliable remote
			expect(lines(harness.fired.client)).is(`R 00 {hex(handshake(Streamed.hash))}\nR 01 01 02 68 69`)
			expect(table.concat(heard, ",")).is("hi")
			expect(#harness.failures.server).is(0)
		end)

		test(
			"Chat rides byte 1 both ways, and every server packet opens with its byte, then the flush's time",
			function ()
				local harness: Harness = connected()
				local heard: { string } = {}
				local ticks: { number } = {}

				harness.server.Chat.on(function (_, text: string)
					table.insert(heard, `server {text}`)
				end)
				harness.client.Chat.on(function (text: string)
					table.insert(heard, `client {text}`)
				end)
				harness.client.Notice.on(function (value: number)
					table.insert(heard, `notice {value}`)
				end)

				harness.mock.time = STAMP
				harness.server.Chat.fire(harness.alice, "yo")
				harness.server.Notice.fire(harness.alice, 7)
				harness.server.Tick.fire(harness.alice, 9)
				harness.client.Chat.fire("hi")
				steps(harness, 2)

				for _, value: number in harness.client.Tick.iter() do
					table.insert(ticks, value)
				end

				-- No order is promised between streams, so what each side heard is compared sorted
				table.sort(heard)

				expect(lines(harness.fired.server)).is(table.concat({
					`R 00 {STAMP_HEX} 02 07`,
					`R 01 {STAMP_HEX} 01 02 79 6F`,
					`U 00 {STAMP_HEX} 03 09 00`,
				}, "\n"))
				expect(lines(harness.fired.client)).is("R 01 01 02 68 69")
				expect(`{table.concat(heard, ",")} tick {table.concat(ticks, ",")}`).is(
					"client yo,notice 7,server hi tick 9"
				)
			end
		)

		test("a Chat and a Notice fired before a late player's handshake are held, each stream in its order", function ()
			local harness: Harness = serve()
			local heard: { Chat: { string }, Notice: { number } } = { Chat = {}, Notice = {} }

			harness.server.Chat.fire(harness.alice, "a")
			harness.server.Notice.fire(harness.alice, 1)
			harness.server.Chat.fire(harness.alice, "b")
			harness.server.Notice.fire(harness.alice, 2)
			steps(harness, 2)

			expect(#harness.fired.server).is(0)

			start(harness)
			harness.client.Chat.on(function (text: string)
				table.insert(heard.Chat, text)
			end)
			harness.client.Notice.on(function (value: number)
				table.insert(heard.Notice, value)
			end)

			-- Her handshake goes, is read and lets out what was held, which she then hears
			steps(harness, 3)

			expect(`{table.concat(heard.Chat, ",")} {table.concat(heard.Notice, ",")}`).is("a,b 1,2")
		end)

		test("Ask's handler fires Notice twice at its caller, and both listeners ran before invoke returns", function ()
			local harness: Harness = connected()
			local box: Box = { line = "pending" }
			local seen: { string } = {}

			harness.server.Ask.on(function (player: any, value: number): number
				harness.server.Notice.fire(player, 1)
				harness.server.Notice.fire(player, 2)
				return value + 1
			end)
			harness.client.Notice.on(function (value: number)
				table.insert(seen, `{value} {box.line}`)
			end)

			into(box, harness.client.Ask.invoke, 5)
			steps(harness, 3)

			expect(table.concat(seen, ",")).is("1 pending,2 pending")
			expect(box.line).is("true 6")
		end)

		test(
			"past a small maxPacket, a second long Chat is dropped as outgoing while the first and an Ask arrive",
			function ()
				local harness: Harness = connected(compiled(`option maxPacket = {CAPPED_PACKET}`))
				local heard: { string } = chats(harness.server)
				local box: Box = { line = "pending" }

				answer(harness.server)

				harness.client.Chat.fire(LONG)
				harness.client.Chat.fire(LONG)
				into(box, harness.client.Ask.invoke, 5)
				steps(harness, 3)

				local report: Report = harness.failures.client[1]

				expect(`{#harness.failures.client} {report.player} {report.kind} {report.detail}`).is(
					"1 nil outgoing over maxPacket, a message was dropped"
				)
				expect(`{#heard} {box.line} {#harness.failures.server}`).is("1 true 6 0")
			end
		)

		test(
			"packets on the default stream and on Bulk spend one packet rate, so the fourth in a second fails",
			function ()
				local harness: Harness = start(serve(compiled(`option maxPacketsPerSecond = {PACKETS}`)))
				local heard: { string } = chats(harness.server)
				local box: Box = { line = "pending" }

				answer(harness.server)

				-- The handshake and Chat a in the first frame, then Ask's call and Chat b: two packets on each stream
				harness.client.Chat.fire("a")
				harness.mock:step()
				into(box, harness.client.Ask.invoke, 5)
				harness.client.Chat.fire("b")
				steps(harness, 3)

				local report: Report = harness.failures.server[1]

				expect(`{#harness.failures.server} {report.kind} {report.detail}`).is(
					`1 rate over {PACKETS} packets a second`
				)
				expect(`{table.concat(heard, ",")} {box.line}`).is("a true 6")
			end
		)

		test("unchecked, a Chat that raises part way leaves nothing in its stream, so the next goes alone", function ()
			local harness: Harness = connected(compiled("option writeValidation = false"))
			local heard: { string } = chats(harness.server)
			local ok: boolean, raised: any = pcall(harness.client.Chat.fire, 42)

			harness.client.Chat.fire("ok")
			steps(harness, 2)

			expect(`{ok} {tostring(raised):sub(1, 6)}`).is("false Chat: ")
			expect(lines(harness.fired.client)).is("R 01 01 02 6F 6B")
			expect(table.concat(heard, ",")).is("ok")
		end)

		test("beforeSend vetoes a Chat, and rate lets one of two through with one rate failure", function ()
			local harness: Harness = connected()
			local heard: { string } = chats(harness.server)

			harness.server.rate("Chat", 1)
			harness.client.hooks.beforeSend("Chat", function (_, text: string): boolean
				return text ~= "no"
			end)

			harness.client.Chat.fire("no")
			harness.client.Chat.fire("a")
			harness.client.Chat.fire("b")
			steps(harness, 2)

			local report: Report = harness.failures.server[1]

			expect(`{table.concat(heard, ",")} {harness.client.stats().rejected}`).is("a 1")
			expect(`{#harness.failures.server} {report.kind} {report.detail}`).is("1 rate Chat: over 1 a second")
		end)
	end)
end)
