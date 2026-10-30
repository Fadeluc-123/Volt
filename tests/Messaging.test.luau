--[[
    Proves the compiler's half of ordered events, channels and the stamp:
    channels numbered and capped, the budget and the client's frame held
    to the bytes a packet opens with, the canonical form and hash, and the
    writers, readers, rows, schema table and accessor the modules carry
--]]

--!strict
local fs = require("@lune/fs")

local Suite = require("./Suite")
local Generated = require("./Generated")
local rendered = require("./Rendered")
local Analyse = require("@volt/Compiler/Analyse")
local Diagnostics = require("@volt/Compiler/Diagnostics")
local Lexer = require("@volt/Compiler/Lexer")
local Parser = require("@volt/Compiler/Parser")
local Print = require("@volt/Compiler/Analyse/Print")
local Resolve = require("@volt/Compiler/Resolve")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Source = require("@volt/Compiler/Source")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

-- The two options every schema must carry, so a fragment compiles clean
local HEADER: string = `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"\n`
local EXAMPLE: string = fs.readFile("tests/Schemas/Example.volt") -- The design's complete example
local EVENTS: string = fs.readFile("tests/Schemas/Events.volt") -- A schema with no channel, ordered event or stamp

-- Two channels, one in a namespace, an event on each and one on the default stream, and a stamp; Chat's parameter
-- takes the name of its own channel's send
local STREAMS: string = table.concat({
	"option stamp = true",
	"channel Bulk",
	"namespace Net {",
	"\tchannel Fast",
	"\tevent Move { from: Server, type: Reliable, call: ManySync, data: u8, channel: Fast }",
	"}",
	"event Chat { from: Both, type: Reliable, call: ManySync, data: (beginReliable_Bulk: string(0..200)), channel: Bulk }",
	"event Notice { from: Server, type: Reliable, call: ManySync, data: u8 }",
}, "\n")

-- A two-way ordered event whose fields take the names of the sequence's send and its reader's local, and a plain
-- unreliable event
local ORDERED: string = table.concat({
	"event Aim { from: Both, type: OrderedUnreliable, call: SingleSync, data: (orderUnreliable: u8, sequence: u16) }",
	"event Spray { from: Server, type: Unreliable, call: ManyAsync, data: u8 }",
}, "\n")

local function schema(fragment: string): string
	return `{HEADER}{fragment}`
end

--[[
    Runs a text through every stage before the generator, returning the
    file, its diagnostics and the schema hash
--]]

local function compile(text: string): (Schema.File, Diagnostics.Diagnostics, number)
	local diagnostics: Diagnostics.Diagnostics = Diagnostics.new(Source.new("Test.volt", text))
	local file: Schema.File = Parser.parse(Lexer.scan(diagnostics.source, diagnostics), diagnostics)

	Resolve.file(file, diagnostics)
	return file, diagnostics, Analyse.file(file, diagnostics)
end

local function report(text: string): string
	local diagnostics: Diagnostics.Diagnostics = select(2, compile(text))
	return diagnostics:render()
end

-- Whether a text holds another, matched plainly
local function holds(text: string, part: string): boolean
	return text:find(part, 1, true) ~= nil
end

describe("Messaging", function ()
	describe("analysis", function ()
		test("numbers channels from 1 in declaration order, depth first, taking no message id", function ()
			local text: string = schema(
				"channel A\nnamespace N { channel B namespace M { channel C } }\nchannel D\nevent E { from: Client, type: Reliable, call: Polling, channel: D }"
			)
			local file: Schema.File, diagnostics = compile(text)
			local a: any, n: any, d: any, e: any = table.unpack(file.declarations)
			local b: any, m: any = table.unpack(n.declarations)

			expect(diagnostics:render()).is("")
			expect(a.number).is(1)
			expect(b.number).is(2)
			expect(m.declarations[1].number).is(3)
			expect(d.number).is(4)
			expect(e.toServer).is(1)
		end)

		test("V3014 refuses a 256th channel at its name, past what the channel byte numbers", function ()
			local channels: { string } = {}
			for index: number = 1, 256 do
				table.insert(channels, `channel C{index}`)
			end

			local text: string = schema(table.concat(channels, "\n"))
			local message: string = "error V3014: a schema declares at most 255 channels"

			expect(report(text)).is(rendered(text, "C256", message))
		end)

		test(
			"V3010 counts an ordered event's sequence, the stamp a server packet opens with and the channel byte",
			function ()
				local over: string = "over the unreliable budget of"

				-- Each schema holds an event exactly at the budget and one a byte past it, whose type key is the nth
				local cases: { { any } } = {
					{
						"option unreliableBudget = 4\nevent Fits { from: Client, type: OrderedUnreliable, call: Polling, data: u8 }\nevent Aim { from: Client, type: OrderedUnreliable, call: Polling, data: u16 }",
						`event Aim can reach 5 bytes, {over} 4`,
						2,
					},
					{
						"option unreliableBudget = 10\noption stamp = true\nevent Fits { from: Server, type: Unreliable, call: Polling, data: u8 }\nevent Up { from: Client, type: Unreliable, call: Polling, data: buffer(9) }\nevent Tick { from: Server, type: Unreliable, call: Polling, data: u16 }",
						`event Tick can reach 11 bytes with the 8-byte stamp, {over} 10`,
						3,
					},
					{
						"option unreliableBudget = 4\nchannel Bulk\nevent Fits { from: Client, type: Unreliable, call: Polling, data: (a: u8, b: u8) }\nevent Big { from: Client, type: Unreliable, call: Polling, data: u24 }",
						`event Big can reach 5 bytes with the channel byte, {over} 4`,
						2,
					},
					{
						"option unreliableBudget = 12\noption stamp = true\nchannel Bulk\nevent Fits { from: Both, type: OrderedUnreliable, call: Polling }\nevent Big { from: Server, type: Unreliable, call: Polling, data: (a: u16, b: u8) }",
						`event Big can reach 13 bytes with the 8-byte stamp and the channel byte, {over} 12`,
						2,
					},
				}

				for _, case: { any } in cases do
					local text: string = schema(case[1])
					expect(report(text)).is(rendered(text, "type", `error V3010: {case[2]}`, case[3]))
				end
			end
		)

		test("V3012 counts the channel byte beside the handshake on every reliable message a client sends", function ()
			local fragment: string =
				"event Fits { from: Client, type: Reliable, call: Polling, data: (a: u32, b: u16) }\nevent Small { from: Both, type: Reliable, call: Polling, data: (a: u32, b: u8) }"
			local plain: string = schema(`option maxPacket = 12\n{fragment}`)
			local channelled: string = schema(`option maxPacket = 12\nchannel Bulk\n{fragment}`)
			local message: string =
				"error V3012: event Fits can reach 7 bytes, over maxPacket 12 with the 5-byte handshake and the channel byte"

			expect(report(plain)).is("")
			expect(report(channelled)).is(rendered(channelled, "Fits", message))
		end)

		test("prints channels, a channel key as a full path, an ordered type and a stamp only when used", function ()
			local file: Schema.File, diagnostics = compile(schema(`{STREAMS}\n{ORDERED}`))
			local printed: string = Print.file(file)
			local lines: { string } = {
				"\noption stamp = true\n",
				"\nchannel Bulk\n",
				"\n\tchannel Fast\n",
				"channel: Net.Fast }",
				"channel: Bulk }",
				"type: OrderedUnreliable,",
			}

			expect(diagnostics:render()).is("")
			for _, line: string in lines do
				expect(holds(printed, line)).is(true)
			end

			local unstamped: Schema.File = compile(schema("option stamp = false"))
			expect(holds(Print.file(unstamped), "stamp")).is(false)
		end)

		test("keeps the hash of a schema with no channel, ordered event or stamp, and a stamp changes it", function ()
			local hash: number = select(3, compile(EXAMPLE))

			expect(select(3, compile(`option stamp = false\n{EXAMPLE}`))).is(hash)
			expect(select(3, compile(`option stamp = true\n{EXAMPLE}`))).never_is(hash)
		end)
	end)

	describe("modules", function ()
		local client: string, server: string = Generated.modules("Streams", schema(STREAMS))
		local orderedClient: string, orderedServer: string = Generated.modules("Ordered", schema(ORDERED))

		test(
			"a channel event's writer takes its channel's sends, which the module takes from runtime.streams",
			function ()
				for _, text: string in { client, server } do
					expect(holds(text, "local offset: number, out: buffer = beginReliable_Bulk(")).is(true)
					expect(holds(text, "trimReliable_Bulk(offset)")).is(true)
					expect(holds(text, "local beginReliable_Bulk: (number) -> (number, buffer)")).is(true)
					expect(holds(text, "beginReliable_Bulk = runtime.streams[1].begin")).is(true)
					expect(holds(text, `stamp = true,\n\tstreams = \{ "Bulk", "Net_Fast" },`)).is(true)
				end

				expect(holds(server, "beginReliable_Net_Fast = runtime.streams[2].begin")).is(true)
				expect(holds(server, "local function writeChat(beginReliable_Bulk_2: string)")).is(true)
			end
		)

		test(
			"a send local is found bounded, so the default stream's is declared only where a writer calls it",
			function ()
				expect(holds(client, "local beginReliable:")).is(false)
				expect(holds(server, "local beginReliable: (number) -> (number, buffer)")).is(true)
			end
		)

		test(
			"a channel event's row names its stream, and a server fire points that stream's send at the player",
			function ()
				expect(holds(client, `\{ name = "Chat", kind = "event", reliable = true, stream = 1, minBytes = 2,`)).is(
					true
				)
				expect(holds(server, `\{ name = "Net.Move", kind = "event", reliable = true, stream = 2,`)).is(true)
				expect(holds(server, "and runtime:target(player, 2) then\n\t\t\t\t\twriteNet_Move(value)")).is(true)
				expect(holds(server, "and runtime:target(player, 1) then\n\t\t\t\twriteChat(")).is(true)
				expect(holds(server, "and runtime:target(player) then\n\t\t\t\twriteNotice(value)")).is(true)
			end
		)

		test("an ordered writer writes its sequence after the id and its reader ends in ordered", function ()
			for _, text: string in { orderedClient, orderedServer } do
				expect(holds(text, "buffer.writeu16(out, offset + 1, orderUnreliable(1))")).is(true)
				expect(holds(text, "local function writeAim(orderUnreliable_2: number, sequence: number)")).is(true)
				expect(holds(text, "local sequence: number = buffer.readu16(packet, cursor)")).is(true)
				expect(holds(text, "local sequence_2: number = buffer.readu16(packet, cursor + 3)")).is(true)
				expect(holds(text, "return runtime:ordered(1, sequence, player, cursor, sideCursor,")).is(true)
				expect(holds(text, "orderUnreliable = runtime.unreliable.order")).is(true)
				expect(holds(text, "reliable = false, sequence = 1, minBytes = 6, maxBytes = 6 }")).is(true)
			end

			expect(holds(orderedServer, `\{ name = "Spray", kind = "event", reliable = false, minBytes = 2,`)).is(true)
		end)

		test("a schema with none of them carries no stamp, stream, sequence or accessor", function ()
			local plainClient: string, plainServer: string = Generated.modules("Events", EVENTS)

			for _, text: string in { plainClient, plainServer, orderedClient, orderedServer } do
				expect(holds(text, "stamp =")).is(false)
				expect(holds(text, "streams")).is(false)
				expect(holds(text, "serverTime")).is(false)
			end

			for _, text: string in { plainClient, plainServer } do
				expect(holds(text, "orderUnreliable")).is(false)
				expect(holds(text, "sequence")).is(false)
			end
		end)

		test("a stamped client has serverTime in the schema's casing, after stats, and the server has none", function ()
			local cases: { { string } } =
				{ { "camel", "serverTime" }, { "pascal", "ServerTime" }, { "snake", "server_time" } }

			for _, case: { string } in cases do
				local cased: string, casedServer: string =
					Generated.modules("Streams", schema(`option casing = {case[1]}\n{STREAMS}`))

				expect(holds(cased, `{case[2]} = function (): number\n\t\treturn runtime:serverTime()`)).is(true)
				expect(holds(casedServer, case[2])).is(false)
			end

			local stats: number = client:find("stats = function", 1, true) :: number
			local accessor: number = client:find("serverTime = function", 1, true) :: number

			expect(stats < accessor).is(true)
		end)
	end)
end)
