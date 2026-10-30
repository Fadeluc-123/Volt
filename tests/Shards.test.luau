--[[
    Proves sharding, Oak's C7: Sharded.volt renders as an entry and three
    shards a side and its types module, and without its shardSize as one
    file a side under the same hash; over the mock the sharded modules
    hold the one-file surface and carry messages, and V4003 refuses what
    no split can fit
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local golden = require("./Expected")
local Volt = require("@volt")
local Output = require("@volt/Compiler/Config/Output")
local Pieces = require("@volt/Compiler/Targets/Pieces")
local Targets = require("@volt/Compiler/Targets")
local TargetsTypes = require("@volt/Compiler/Config/Types/Targets")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Extra = TargetsTypes.Extra
type Mock = Volt.Mock

-- A server and Alice's client over one mock, each running its side's module with its shards answered by name
type Harness = { mock: Mock, alice: any, server: any, client: any }

local FILE_LOCALS: number = Output.fileLocals
local SCHEMA: string = fs.readFile("tests/Schemas/Sharded.volt")
local PLAIN: string = (SCHEMA:gsub("option shardSize[^\n]*\n", ""))
local CLIENT: string, SERVER: string, TYPES: string, EXTRA: { Extra } = Generated.modules("Sharded", SCHEMA)
local PLAIN_CLIENT: string, PLAIN_SERVER: string, _: string, PLAIN_EXTRA: { Extra } =
	Generated.modules("Sharded", PLAIN)
local MAPS: { string } = { "events", "functions", "exports" }
local WAITS: { string } = { "WaitForChild", "task.wait" } -- What a module that waits on its remotes would call

-- Each entry of Sharded.volt with the shard that holds it, packed three to a shard in declaration order
local PACKED: { string } = {
	`Shard1.handles["Save"]`,
	`Shard1.handles["Input"]`,
	`Shard1.handles["Ready"]`,
	`Shard2.handles["Sync"]`,
	`Shard2.handles["Inventory.Patch"]`,
	`Shard2.handles["Inventory.Transfer"]`,
	`Shard3.handles["Inventory.Picked"]`,
	`Shard3.handles["Echo"]`,
}

-- The two outputs every schema built here sets, its other options, each line ended, then its declarations
local function schema(declarations: { string }, options: string?): string
	local head: string = `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"\n{options or ""}`
	return `{head}{table.concat(declarations, "\n")}`
end

-- Each shard's text by the string its entry requires it with
local function required(extra: { Extra }): { [string]: string }
	local map: { [string]: string } = {}
	for _, file: Extra in extra do
		map[`./{file.output:match("^(.-)%.luau$")}`] = file.text
	end
	return map
end

local function setup(client: string, server: string, extra: { Extra }): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local alice: any, transport = mock:join("Alice")
	local shards: { [string]: string } = required(extra)

	return {
		mock = mock,
		alice = alice,
		server = (Generated.module("Server", server, mock.server, shards)),
		client = (Generated.module("Client", client, transport, shards)),
	}
end

local function steps(mock: Mock, count: number)
	for _ = 1, count do
		mock:step()
	end
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

-- A table named, then whether it is frozen and whether it has no metatable
local function sealed(label: string, value: any): string
	return `{label} {table.isfrozen(value)} {getmetatable(value) == nil}`
end

-- The entry a registry name stands for, read through a module's namespaces
local function nested(module: any, path: string): any
	local value: any = module
	for name: string in path:gmatch("[^.]+") do
		value = value[name]
	end
	return value
end

-- What assembling a schema text's modules reported
local function refused(name: string, text: string): (number, string)
	local file, hash, diagnostics = Generated.compile(name, text)

	Targets.modules(file, diagnostics, hash)

	return diagnostics.errors, diagnostics:render()
end

describe("Shards", function ()
	local files: { { name: string, text: string } } =
		{ { name = "Client", text = CLIENT }, { name = "Server", text = SERVER }, { name = "Types", text = TYPES } }

	for _, file: Extra in EXTRA do
		table.insert(files, { name = file.output:match("^(.-)%.luau$") :: string, text = file.text })
	end

	test("writes an entry a side with three shards beside it, and the types module", function ()
		local outputs: { string } = {}
		for _, file: Extra in EXTRA do
			table.insert(outputs, file.output)
		end

		expect(table.concat(outputs, " ")).is(
			"ClientShard1.luau ClientShard2.luau ClientShard3.luau ServerShard1.luau ServerShard2.luau ServerShard3.luau"
		)
	end)

	for _, file in files do
		test(`renders {file.name} as its golden file`, function ()
			expect(golden("tests/Golden/Sharded", file.name, file.text)).is(file.text)
		end)
	end

	test("packs the entries three to a shard in declaration order, on both sides", function ()
		for _, entry: string in PACKED do
			expect(`{entry} {CLIENT:find(entry, 1, true) ~= nil} {SERVER:find(entry, 1, true) ~= nil}`).is(
				`{entry} true true`
			)
		end
	end)

	test("compiles without its shardSize to one file a side and no shard, under the same hash", function ()
		local _, hash: number = Generated.compile("Sharded", SCHEMA)
		local _, plainHash: number = Generated.compile("Sharded", PLAIN)

		expect(#PLAIN_EXTRA).is(0)
		expect(hash).is(plainHash)
		expect(SERVER:match("hash = 0x%x+")).is(PLAIN_SERVER:match("hash = 0x%x+"))
		expect(PLAIN_SERVER:find(`require("./`, 1, true) == nil).is(true)
	end)

	test("neither the server entry nor any server shard waits on anything", function ()
		local texts: { string } = { SERVER }
		for _, file: Extra in EXTRA do
			if file.output:match("^Server") then
				table.insert(texts, file.text)
			end
		end

		for _, text: string in texts do
			for _, wait: string in WAITS do
				expect(text:find(wait, 1, true) == nil).is(true)
			end
		end

		expect(#texts).is(4)
	end)

	describe("over the mock", function ()
		test("each side holds the one-file surface: the same keys, frozen, no metatable, the maps' handles", function ()
			local sharded: Harness = setup(CLIENT, SERVER, EXTRA)
			local plain: Harness = setup(PLAIN_CLIENT, PLAIN_SERVER, PLAIN_EXTRA)

			for _, side: string in { "server", "client" } do
				local module: any = (sharded :: any)[side]
				local one: any = (plain :: any)[side]

				expect(keys(module)).is(keys(one))
				expect(keys(module.Inventory)).is(keys(one.Inventory))
				expect(module.version).is(one.version)
				expect(sealed(side, module)).is(`{side} true true`)
				expect(sealed("Inventory", module.Inventory)).is("Inventory true true")

				for _, map: string in MAPS do
					expect(keys(module[map])).is(keys(one[map]))
					expect(sealed(map, module[map])).is(`{map} true true`)

					for name: string, handle: any in module[map] do
						expect(`{side} {name} {rawequal(handle, nested(module, name))}`).is(`{side} {name} true`)
						expect(`{side} {name} {keys(handle)}`).is(`{side} {name} {keys(one[map][name])}`)
						expect(sealed(name, handle)).is(`{name} true true`)
					end
				end
			end
		end)

		test("a client's Input reaches the server's listener, Echo comes back, and Sync crosses both ways", function ()
			local harness: Harness = setup(CLIENT, SERVER, EXTRA)
			local heard: { string } = {}
			local answered: string = "pending"

			harness.server.Input.on(function (player: any, dir: number, jump: boolean)
				table.insert(heard, `input {player.Name} {dir} {jump}`)
			end)
			harness.server.Sync.on(function (_, value: number)
				table.insert(heard, `server sync {value}`)
			end)
			harness.client.Sync.on(function (value: number)
				table.insert(heard, `client sync {value}`)
			end)
			harness.server.Echo.on(function (_, value: number): number
				return value
			end)

			harness.client.Input.fire(5, true)
			harness.client.Sync.fire(1)
			harness.server.Sync.fire(harness.alice, 2)

			task.spawn(function ()
				local ok: boolean, value: number? = harness.client.Echo.invoke(42)
				answered = `{ok} {value}`
			end)

			steps(harness.mock, 3)
			table.sort(heard)

			expect(table.concat(heard, ",")).is("client sync 2,input Alice 5 true,server sync 1")
			expect(answered).is("true 42")
		end)

		test(
			"a shard declares the channel's and the dictionary's locals its functions name, and carries them",
			function ()
				local streams: string = `option shardSize = 1\n{fs.readFile("tests/Schemas/Streams.volt")}`
				local dictionary: string = `option shardSize = 1\n{fs.readFile("tests/Schemas/Dictionary.volt")}`
				local streamsClient: string, streamsServer: string, _: string, streamsExtra: { Extra } =
					Generated.modules("Streams", streams)
				local dictionaryClient: string, dictionaryServer: string, _: string, dictionaryExtra: { Extra } =
					Generated.modules("Dictionary", dictionary)
				local chat: Harness = setup(streamsClient, streamsServer, streamsExtra)
				local picked: Harness = setup(dictionaryClient, dictionaryServer, dictionaryExtra)
				local heard: { string } = {}

				chat.server.Chat.on(function (player: any, text: string)
					table.insert(heard, `{player.Name} {text}`)
				end)
				chat.client.Chat.on(function (text: string)
					table.insert(heard, `server {text}`)
				end)
				picked.client.picked.on(function (item: string, title: string)
					table.insert(heard, `{item} {title}`)
				end)

				chat.client.Chat.fire("hi")
				chat.server.Chat.fire(chat.alice, "yo")
				picked.server.picked.fire(picked.alice, "Sword", "Scout")
				steps(chat.mock, 3)
				steps(picked.mock, 5)
				table.sort(heard)

				expect(#streamsExtra).is(8)
				expect(#dictionaryExtra).is(6)
				expect(table.concat(heard, ",")).is("Alice hi,Sword Scout,server yo")
			end
		)
	end)

	test("shards a side past fileLocals with no shardSize, the first shard full and none past it", function ()
		local events: { string } = {}
		for index: number = 1, FILE_LOCALS + 10 do
			table.insert(events, `event E{index} \{ from: Client, type: Reliable, call: ManySync }`)
		end

		local client: string, server: string, _: string, extra: { Extra } = Generated.modules("Many", schema(events))
		local counts: { [string]: number } = { Client = 0, Server = 0 }

		for _, file: Extra in extra do
			local side: string = file.output:match("^(%a-)Shard") :: string

			counts[side] += 1
			expect(Pieces.declared(file.text) <= FILE_LOCALS).is(true)
		end

		expect(Pieces.declared(extra[1].text)).is(FILE_LOCALS)
		expect(`{counts.Client} {counts.Server}`).is("2 2")
		expect(Pieces.declared(client) <= FILE_LOCALS and Pieces.declared(server) <= FILE_LOCALS).is(true)
	end)

	test("V4003 refuses an entry that alone needs more locals than one file holds, on each side", function ()
		local declarations: { string } = {}
		local fields: { string } = {}

		for index: number = 1, FILE_LOCALS do
			table.insert(declarations, `export type T{index} = u8`)
			table.insert(fields, `field{index}: T{index}`)
		end

		table.insert(
			declarations,
			`event Big \{ from: Client, type: Reliable, call: ManySync, data: struct \{ {table.concat(fields, ", ")} } }`
		)

		-- Reported at the event's name, the last line after the two options
		local errors: number, rendered: string = refused("Big", schema(declarations))
		local location: string = `Big.volt:{#declarations + 2}:7: error V4003`
		local message: string =
			"Big needs 154 module-level locals on the server, more than one generated file holds (150)"

		expect(errors).is(2)
		expect(rendered:find(`{location}: {message}`, 1, true) ~= nil).is(true)
	end)

	test("V4003 refuses a side needing more shards than its entry can require", function ()
		local events: { string } = {}
		for index: number = 1, FILE_LOCALS do
			table.insert(events, `event E{index} \{ from: Client, type: Reliable, call: ManySync }`)
		end

		local errors: number, rendered: string = refused("Many", schema(events, "option shardSize = 1\n"))
		local expected: string =
			"error V4003: the server module needs 150 shards, more than its entry can require (146)"

		expect(errors).is(2)
		expect(rendered:find(expected, 1, true) ~= nil).is(true)
	end)
end)
