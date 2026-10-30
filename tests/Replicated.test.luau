--[[
    Proves the modules the replication attributes compile to: each side
    of Deltas and Dictionary renders as its golden file, the dictionary's
    locals and row appear only where a @dictionary type needs them, and
    over the mock a @delta fire at no player raises, a patch merges into
    the whole struct, and dictionary strings cross both ways
--]]

--!strict
local fs = require("@lune/fs")
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local golden = require("./Expected")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Mock = Volt.Mock
type Runtime = Volt.Runtime

-- A server and Alice's client over one mock, each running its side's module, with the server's runtime
type Harness = { mock: Mock, alice: any, server: any, runtime: Runtime, client: any }

local SCHEMAS: string = "tests/Schemas"
local NONE: string = "Volt: a message for one player was sent to none"

local DELTAS_CLIENT: string, DELTAS_SERVER: string, DELTAS_TYPES: string =
	Generated.modules("Deltas", fs.readFile(`{SCHEMAS}/Deltas.volt`))
local DICTIONARY_CLIENT: string, DICTIONARY_SERVER: string =
	Generated.modules("Dictionary", fs.readFile(`{SCHEMAS}/Dictionary.volt`))

local GOLDENS: { { directory: string, name: string, text: string } } = {
	{ directory = "tests/Golden/Deltas", name = "Client", text = DELTAS_CLIENT },
	{ directory = "tests/Golden/Deltas", name = "Server", text = DELTAS_SERVER },
	{ directory = "tests/Golden/Deltas", name = "Types", text = DELTAS_TYPES },
	{ directory = "tests/Golden/Dictionary", name = "Client", text = DICTIONARY_CLIENT },
	{ directory = "tests/Golden/Dictionary", name = "Server", text = DICTIONARY_SERVER },
}

-- What a module of a schema with a @dictionary type names, and no other module does
local DICTIONARY_NAMES: { string } = { "internDictionary", "dictionaryEntries", "\tdictionary = " }

-- Alice's first vitals, whole, and the next, with only her health changed
local FIRST: { [string]: any } =
	{ health = 100, stamina = 50, title = "Scout", held = 7, gear = { shield = true, boots = false } }
local SECOND: { [string]: any } =
	{ health = 90, stamina = 50, title = "Scout", held = 7, gear = { shield = true, boots = false } }

-- A server over one mock with Alice joined and her client started, each running its side of the modules given
local function setup(client: string, server: string): Harness
	local mock: Mock = Volt.mock(task.spawn)
	local alice: any, transport = mock:join("Alice")
	local module: any, runtime: Runtime = Generated.module("Server", server, mock.server)

	return {
		mock = mock,
		alice = alice,
		server = module,
		runtime = runtime,
		client = Generated.module("Client", client, transport),
	}
end

-- Enough steps for a server fire to reach a client whose handshake was not read yet, or for a reply to come back
local function steps(mock: Mock, count: number)
	for _ = 1, count do
		mock:step()
	end
end

-- A delivered vitals as one line, its nested struct included
local function line(value: { [string]: any }): string
	local gear: { [string]: any } = value.gear
	return `{value.health} {value.stamina} {value.title} {value.held} {gear.shield} {gear.boots}`
end

describe("Replicated", function ()
	for _, entry in GOLDENS do
		local module: string = `{entry.directory:match("[^/]+$")} {entry.name:lower()}`

		test(`renders the {module} module as its golden file`, function ()
			expect(golden(entry.directory, entry.name, entry.text)).is(entry.text)
		end)
	end

	test("names the dictionary's locals and row only in a module of a schema with a @dictionary type", function ()
		for _, name: string in fs.readDir(SCHEMAS) do
			local schema: string? = name:match("^(.+)%.volt$")
			local text: string = schema and fs.readFile(`{SCHEMAS}/{name}`) or ""

			if schema and schema ~= "Dictionary" and not text:find("@dictionary", 1, true) then
				local client: string, server: string = Generated.modules(schema, text)

				for _, piece: string in DICTIONARY_NAMES do
					expect(`{schema} {client:find(piece, 1, true) ~= nil} {server:find(piece, 1, true) ~= nil}`).is(
						`{schema} false false`
					)
				end
			end
		end

		-- The server writes the strings and the client reads them, and both tell the runtime the id's width
		expect(DICTIONARY_SERVER:find("internDictionary(", 1, true) ~= nil).is(true)
		expect(DICTIONARY_SERVER:find("dictionaryEntries", 1, true) == nil).is(true)
		expect(DICTIONARY_CLIENT:find("dictionaryEntries[", 1, true) ~= nil).is(true)
		expect(DICTIONARY_CLIENT:find("internDictionary", 1, true) == nil).is(true)
		expect(DICTIONARY_SERVER:find("\tdictionary = 1,", 1, true) ~= nil).is(true)
		expect(DICTIONARY_CLIENT:find("\tdictionary = 1,", 1, true) ~= nil).is(true)
	end)

	describe("over the mock", function ()
		test("a @delta fire at no player raises, writing nothing, while a fireAll after it goes whole", function ()
			local harness: Harness = setup(DELTAS_CLIENT, DELTAS_SERVER)
			local heard: { string } = {}

			harness.client.vitals.on(function (value: { [string]: any })
				table.insert(heard, line(value))
			end)

			local ok: boolean, message: any = pcall(harness.server.vitals.fire, nil, FIRST)

			expect(ok).is(false)
			expect(tostring(message):find(NONE, 1, true) ~= nil).is(true)

			harness.server.vitals.fireAll(FIRST)
			steps(harness.mock, 3)

			expect(table.concat(heard, ",")).is("100 50 Scout 7 true false")
		end)

		test("a patch carries the changed field alone and is heard merged into a frozen whole struct", function ()
			local harness: Harness = setup(DELTAS_CLIENT, DELTAS_SERVER)
			local heard: { { [string]: any } } = {}

			harness.client.vitals.on(function (value: { [string]: any })
				table.insert(heard, value)
			end)

			harness.server.vitals.fire(harness.alice, FIRST)
			steps(harness.mock, 3)

			local before: number = harness.server.stats(harness.alice).bytesOut

			harness.server.vitals.fire(harness.alice, SECOND)
			steps(harness.mock, 2)

			-- The id, the mask and the one byte of health
			expect(harness.server.stats(harness.alice).bytesOut - before).is(3)
			expect(`{line(heard[1])},{line(heard[2])}`).is("100 50 Scout 7 true false,90 50 Scout 7 true false")
			expect(table.isfrozen(heard[2])).is(true)
		end)

		test("a polled @delta event of an inline struct drains whole, then patched", function ()
			local harness: Harness = setup(DELTAS_CLIENT, DELTAS_SERVER)
			local rows: { string } = {}

			harness.server.zone.fire(harness.alice, { id = 4, safe = true })
			steps(harness.mock, 3)
			harness.server.zone.fire(harness.alice, { id = 4, safe = false })
			steps(harness.mock, 2)

			for index: number, value: { [string]: any } in harness.client.zone.iter() do
				table.insert(rows, `{index} {value.id} {value.safe}`)
			end

			expect(table.concat(rows, ",")).is("1 4 true,2 4 false")
		end)

		test("dictionary strings cross in a pack, a map's keys and the structs it holds, and a reply", function ()
			local harness: Harness = setup(DICTIONARY_CLIENT, DICTIONARY_SERVER)
			local heard: { string } = {}
			local answered: string = "pending"

			harness.client.picked.on(function (item: string, title: string)
				table.insert(heard, `{item} {title}`)
			end)
			harness.client.stock.on(function (stock: { [string]: { title: string, count: number } })
				table.insert(heard, `{stock.Sword.title} {stock.Sword.count} {stock.Bow.title} {stock.Bow.count}`)
			end)
			harness.server.lookup.on(function (_, id: number): string?
				return id == 1 and "Bow" or nil
			end)

			harness.server.picked.fire(harness.alice, "Sword", "Scout")
			harness.server.stock.fire(harness.alice, {
				Sword = { title = "Scout", count = 2 },
				Bow = { title = "Hunter", count = 1 },
			})

			task.spawn(function ()
				local ok: boolean, item: string? = harness.client.lookup.invoke(1)
				answered = `{ok} {item}`
			end)

			steps(harness.mock, 5)

			-- A map's entries are written in no fixed order, so neither are the strings they add
			local entries: { string } = table.clone(harness.runtime.dictionary)
			table.sort(entries)

			expect(table.concat(heard, ",")).is("Sword Scout,Scout 2 Hunter 1")
			expect(answered).is("true Bow")
			expect(table.concat(entries, ",")).is("Bow,Hunter,Scout,Sword")
		end)

		test("a string outside its bounds, or not UTF-8 where it must be, is refused and never kept", function ()
			local harness: Harness = setup(DICTIONARY_CLIENT, DICTIONARY_SERVER)
			local short: boolean, shortMessage: any = pcall(harness.server.picked.fire, harness.alice, "", "Scout")
			local text: boolean, textMessage: any = pcall(harness.server.picked.fire, harness.alice, "Sword", "\xFF")

			expect(`{short} {shortMessage}`).is("false picked.item: length out of range")
			expect(`{text} {textMessage}`).is("false picked.title: invalid UTF-8")
			expect(table.concat(harness.runtime.dictionary, ",")).is("Sword")
		end)
	end)
end)
