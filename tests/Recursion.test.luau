--[[
    Proves recursive types through the generator: each pair takes its level
    last and checks it first in every build, so a value past its bound is
    refused on both sides and a value that holds itself never runs a writer
    into the call limit; a side keeps a whole cycle with its forward
    declarations, a shard and the inspector among them; and values round-trip
--]]

--!strict
local fs = require("@lune/fs")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes it provides
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local Values = require("./Values")
local golden = require("./Expected")
local packet = require("./Packet")
local Volt = require("@volt")
local Contract = require("@volt/Compiler/Config/Contract")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local TargetsTypes = require("@volt/Compiler/Config/Types/Targets")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Extra = TargetsTypes.Extra
type TypeDeclaration = Schema.TypeDeclaration

-- A server and Alice's client over one mock, each running its side's module, with what each side reported
type Harness = {
	mock: Volt.Mock,
	alice: any,
	transport: Volt.Transport,
	server: any,
	client: any,
	failures: { server: { string }, client: { string } },
}

local SCHEMA: string = fs.readFile("tests/Schemas/Recursive.volt")
local LINKED: string = fs.readFile("tests/Schemas/Linked.volt")
local UNCHECKED: string = `option writeValidation = false\n{SCHEMA}`
local SHARDED: string = `option shardSize = 1\n{SCHEMA}`
local INSPECTED: string = `option inspectorOutput = "Inspector.luau"\n{SCHEMA}`
local HEADER: string = `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"\n`
local SCENE: number = 1 -- The id Scene reaches the server with
local FILES: number = 1 -- The id Files reaches the client with
local DEEPEST: number = 4 -- The bound every type of the schema sets
local WIDEST: number = 3 -- The kids a Tree may hold, so a tree at its bound holds 1 + 3 + 9 + 27 nodes

-- Five levels of empty Trees, its id first, each level a name's length and a count of kids; the fifth is refused
local TOO_DEEP: { number } = { SCENE, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0 }

-- Folder, Entry, Folder, Entry and a fifth level's byte, its id first, each Sub's tag bit set and each count one
local FILES_TOO_DEEP: { number } = { FILES, 1, 1, 1, 1, 0 }

-- Folder > Entry(Sub) > Folder > Entry(File), which sits at the bound of both types
local FOLDER: { [string]: any } = {
	entries = { { kind = "Sub", folder = { entries = { { kind = "File", size = 7 } } } } },
}

-- The wire table's example: root's two fixed bytes and its four, then a's two fixed bytes and its one
local ROOT: { [string]: any } = { name = "root", kids = { { name = "a", kids = {} } } }
local ROOT_BYTES: { number } = { 4, 1, 0x72, 0x6F, 0x6F, 0x74, 1, 0, 0x61 }

local file: Schema.File = Generated.compile("Recursive", SCHEMA)
local TREE: Schema.Type = (file.declarations[1] :: TypeDeclaration).type
local FOLDERS: Schema.Type = (file.declarations[2] :: TypeDeclaration).type

-- Each shard's text by the string its entry requires it with
local function required(extra: { Extra }): { [string]: string }
	local map: { [string]: string } = {}
	for _, shard: Extra in extra do
		map[`./{shard.output:match("^(.-)%.luau$")}`] = shard.text
	end
	return map
end

-- A list that keeps every failure a module reports, as its kind and detail
local function recorded(module: any): { string }
	local reports: { string } = {}

	module.onFailure(function (_, kind: string, detail: string)
		table.insert(reports, `{kind} {detail}`)
	end)

	return reports
end

local function setup(text: string): Harness
	local client: string, server: string, _: string, extra: { Extra } = Generated.modules("Recursive", text)
	local mock: Volt.Mock = Volt.mock(task.spawn)
	local alice: any, transport: Volt.Transport = mock:join("Alice")
	local shards: { [string]: string } = required(extra)
	local serverModule: any = Generated.module("Server", server, mock.server, shards)
	local clientModule: any = Generated.module("Client", client, transport, shards)

	return {
		mock = mock,
		alice = alice,
		transport = transport,
		server = serverModule,
		client = clientModule,
		failures = { server = recorded(serverModule), client = recorded(clientModule) },
	}
end

-- Enough steps for a client's handshake and fire to be read, or for a server's fire to wait it out and arrive
local function steps(mock: Volt.Mock)
	mock:step()
	mock:step()
	mock:step()
end

-- A tree of some levels, each node with as many kids as given
local function tree(levels: number, width: number): { [string]: any }
	local kids: { any } = {}

	for index: number = 1, levels > 1 and width or 0 do
		kids[index] = tree(levels - 1, width)
	end

	return { name = `l{levels}`, kids = kids }
end

local function holds(text: string, part: string): boolean
	return text:find(part, 1, true) ~= nil
end

local function refused(ok: boolean, message: any, expected: string)
	expect(ok).is(false)
	expect(holds(tostring(message), expected)).is(true)
end

-- Fires a client's Scene over a schema's modules and returns what the server's listener heard, in order
local function heardScenes(harness: Harness, values: { any }): { any }
	local heard: { any } = {}

	harness.server.Scene.on(function (_, value: any)
		table.insert(heard, value)
	end)

	for _, value: any in values do
		harness.client.Scene.fire(value)
	end

	steps(harness.mock)

	return heard
end

describe("Recursion", function ()
	local text: string = Generated.render(file)

	test("renders as the golden file", function ()
		expect(golden("tests/Golden/Recursive", "Emit", text)).is(text)
	end)

	test("writes the wire table's example", function ()
		local module: any, written: () -> (buffer, { any }) = Generated.load("Recursive", text)

		module.Scene.write(ROOT)

		expect(buffer.tostring((written()))).is(buffer.tostring(packet(ROOT_BYTES)))
	end)

	describe("round trips", function ()
		test("a client's Scene of one to four levels, the widest of 40 nodes, reaches its listener equal", function ()
			local harness: Harness = setup(SCHEMA)
			local sent: { any } = {}

			for levels: number = 1, DEEPEST do
				sent[levels] = tree(levels, WIDEST)
			end

			local heard: { any } = heardScenes(harness, sent)

			expect(#heard).is(DEEPEST)

			for index: number, value: any in sent do
				expect(Values.near(TREE, value, heard[index])).is(true)
			end
		end)

		test("a server's Files reaches its listener equal, through a cycle of two types", function ()
			local harness: Harness = setup(SCHEMA)
			local heard: any

			harness.client.Files.on(function (value: any)
				heard = value
			end)
			harness.server.Files.fire(harness.alice, FOLDER)
			steps(harness.mock)

			expect(Values.near(FOLDERS, FOLDER, heard)).is(true)
		end)

		test("an exported Tree writes and reads back at its bound, and raises the refusal past it", function ()
			local harness: Harness = setup(SCHEMA)
			local value: { [string]: any } = tree(DEEPEST, WIDEST)
			local bytes: buffer, side: { any }? = harness.client.exports.Tree.write(value)

			expect(Values.near(TREE, value, harness.server.exports.Tree.read(bytes, side))).is(true)

			local ok: boolean, message: any = pcall(harness.client.exports.Tree.write, tree(DEEPEST + 1, 1))
			refused(ok, message, "Tree: nested deeper than 4")
		end)
	end)

	describe("a value past its bound", function ()
		for _, source: string in { SCHEMA, UNCHECKED } do
			test(`is refused at the fire and leaves nothing behind, under {source:match("^[^\n]*")}`, function ()
				local harness: Harness = setup(source)
				local holder: { [string]: any } = { name = "self", kids = {} }

				holder.kids[1] = holder

				local fine: { [string]: any } = tree(1, 1)
				local heard: { any } = {}

				harness.server.Scene.on(function (_, value: any)
					table.insert(heard, value)
				end)

				for _, value: any in { tree(DEEPEST + 1, 1), holder } do
					local ok: boolean, message: any = pcall(harness.client.Scene.fire, value)
					refused(ok, message, "Tree: nested deeper than 4")
				end

				harness.client.Scene.fire(fine)
				steps(harness.mock)

				expect(#heard).is(1)
				expect(Values.near(TREE, fine, heard[1])).is(true)
				expect(#harness.failures.server).is(0)
			end)
		end

		test("is refused by the server's reader, on bytes its writer would never send", function ()
			local harness: Harness = setup(SCHEMA)

			harness.mock:step()
			harness.transport.reliable(nil, packet(TOO_DEEP))
			steps(harness.mock)

			expect(harness.failures.server[1]).is("decode Scene: Tree: nested deeper than 4")
		end)

		test("is refused by the client's reader, at the first type of the cycle to pass", function ()
			local harness: Harness = setup(SCHEMA)

			harness.mock.server.reliable(harness.alice, packet(FILES_TOO_DEEP))
			steps(harness.mock)

			expect(harness.failures.client[1]).is("decode Files: Folder: nested deeper than 4")
		end)

		test("is refused at the tighter bound of a cycle whose types set different ones", function ()
			local source: string =
				`{HEADER}@depth(2) struct A \{ b: B? }\n@depth(9) struct B \{ a: A? }\nevent E \{ from: Client, type: Reliable, call: SingleSync, data: A }`
			local chunk: string = Generated.render((Generated.compile("Tight", source)))
			local module: any = Generated.load("Tight", chunk)

			module.E.write({ b = { a = nil } })

			local ok: boolean, message: any = pcall(module.E.write, { b = { a = { b = nil } } })
			refused(ok, message, "A: nested deeper than 2")
		end)
	end)

	describe("what a side keeps", function ()
		local client: string, server: string = Generated.modules("Recursive", SCHEMA)

		-- Whether a module holds a half both as its forward declaration and as its definition, and neither otherwise
		local function kept(module: string, half: string, expected: boolean)
			expect(holds(module, `\nlocal {half}: (`)).is(expected)
			expect(holds(module, `\nfunction {half}(`)).is(expected)
		end

		test("the server keeps what it sends and what it hears, and no half of a pair it does neither with", function ()
			for _, half: string in { "writeFolder", "writeEntry", "readTree", "writeTree" } do
				kept(server, half, true)
			end
			for _, half: string in { "readFolder", "readEntry" } do
				kept(server, half, false)
			end
		end)

		test("the client keeps the reverse", function ()
			for _, half: string in { "readFolder", "readEntry", "readTree", "writeTree" } do
				kept(client, half, true)
			end
			for _, half: string in { "writeFolder", "writeEntry" } do
				kept(client, half, false)
			end
		end)

		test("each half is called at level 1 from a message and at the next level from a pair", function ()
			expect(holds(client, "writeTree(allocateReliable, slotReliable, refuseReliable, value, 1)")).is(true)
			expect(holds(client, "writeTree(allocate, slot, refuse, kids[index], depth + 1)")).is(true)
			expect(holds(server, "= readTree(packet, cursor, side, sideCursor, length, 1)")).is(true)
			expect(holds(server, "= readTree(packet, cursor, side, sideCursor, length, depth + 1)")).is(true)
		end)
	end)

	describe("sharded", function ()
		test("each shard holds every half it reaches with its forward declaration", function ()
			local extra: { Extra } = select(4, Generated.modules("Recursive", SHARDED))

			expect(#extra > 0).is(true)

			for _, shard: Extra in extra do
				for _, half: string in
					{ "writeFolder", "writeEntry", "writeTree", "readFolder", "readEntry", "readTree" }
				do
					expect(holds(shard.text, `\nlocal {half}: (`)).is(holds(shard.text, `\nfunction {half}(`))
				end

				-- A shard keeps the whole of a cycle it reaches, each side's own halves of it
				expect(holds(shard.text, "\nfunction writeFolder(")).is(holds(shard.text, "\nfunction writeEntry("))
				expect(holds(shard.text, "\nfunction readFolder(")).is(holds(shard.text, "\nfunction readEntry("))
			end
		end)

		test("still round-trips over the mock", function ()
			local harness: Harness = setup(SHARDED)
			local value: { [string]: any } = tree(DEEPEST, WIDEST)
			local heard: { any } = heardScenes(harness, { value })
			local folder: any

			harness.client.Files.on(function (read: any)
				folder = read
			end)
			harness.server.Files.fire(harness.alice, FOLDER)
			steps(harness.mock)

			expect(Values.near(TREE, value, heard[1])).is(true)
			expect(Values.near(FOLDERS, FOLDER, folder)).is(true)
		end)
	end)

	test("the inspector reads a recursive pair at level 1, and notes one past its bound", function ()
		local extra: { Extra } = select(4, Generated.modules("Recursive", INSPECTED))
		local game: any = roblox.Instance.new("DataModel")
		local volt: any = roblox.Instance.new("Folder")
		local scope: any = roblox.Instance.new("Folder")
		local remote: any = roblox.Instance.new("RemoteEvent")

		volt.Name, scope.Name = Contract.folder, "Recursive"
		volt.Parent, scope.Parent, remote.Parent = game:GetService("ReplicatedStorage"), volt, scope

		local inspect: any = Generated.module("Inspector", extra[#extra].text, Volt.mock(task.spawn).server, nil, {
			game = game,
		})
		local bytes: { number } = table.move(ROOT_BYTES, 1, #ROOT_BYTES, 2, { SCENE })
		local calls: { any } = inspect(remote, {}, packet(bytes), {})

		expect(calls[1].Name).is("Scene")
		expect(Values.near(TREE, ROOT, calls[1].Arguments[1])).is(true)
		expect(inspect(remote, {}, packet(TOO_DEEP), {})[1].Name).is("decode: Scene")
	end)

	describe("a generic that contains itself", function ()
		test("is one pair named by its label, annotated by its alias and refused by its path", function ()
			local client: string, server: string = Generated.modules("Linked", LINKED)

			expect(holds(client, "export type Linked<T> = { value: T, next: Linked<T>? }\n")).is(true)
			expect(holds(client, "\nfunction writeLinked_1(")).is(true)
			expect(holds(server, "): (number, number, Linked<number>)\n")).is(true)
			expect(holds(client, `refuse("Linked<u8>: nested deeper than 4")`)).is(true)
			expect(holds(server, `error("Linked<u8>: nested deeper than 4")`)).is(true)
		end)
	end)

	test("a field named depth takes a renamed local and reads back", function ()
		local source: string =
			`{HEADER}@depth(4) struct Cell \{ depth: u8, next: Cell? }\nevent E \{ from: Client, type: Reliable, call: SingleSync, data: Cell }`
		local chunk: string = Generated.render((Generated.compile("Cell", source)))
		local module: any, written: () -> (buffer, { any }) = Generated.load("Cell", chunk)

		module.E.write({ depth = 1, next = { depth = 2 } })

		local bytes: buffer = written()
		local read: any = select(3, module.E.read(bytes, 0, {}, 1, buffer.len(bytes)))

		expect(holds(chunk, "local depth_2")).is(true)
		expect(read.next.depth).is(2)
	end)
end)
