--[[
    Proves the packet inspector, loaded as PacketProfiler finds it, in a
    place holding its scope's remotes, and handed the packets a server and
    a client wrote: it reads each side's messages with their values, for
    display alone and never raising; and a schema's inspector reads its
    channel byte, its stamp, an ordered sequence, the dictionary message,
    an awaited instance's and a dictionary string's ids, and a @delta
    message's mask and fields
--]]

--!strict
local fs = require("@lune/fs")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes it provides
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local packet = require("./Packet")
local profiled = require("./Profiled")
local Volt = require("@volt")
local Runtime = require("@volt/Config/Runtime")
local Contract = require("@volt/Compiler/Config/Contract")
local Output = require("@volt/Compiler/Config/Output")
local Targets = require("@volt/Compiler/Targets")
local TargetsTypes = require("@volt/Compiler/Config/Types/Targets")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Calls = { { Name: string, Arguments: { any } } }?
type Extra = TargetsTypes.Extra
type Harness = profiled.Harness
type Kept = profiled.Kept

local FILE_LOCALS: number = Output.fileLocals
local SCHEMA: string = fs.readFile("tests/Schemas/Tooling.volt")
local INSPECTED: string = `option inspectorOutput = "Inspector.luau"\n` -- Put before another schema's text, for its inspector
local NAME: string = string.rep("n", 17) -- One byte past the 16 Entry.name holds

local function steps(harness: Harness, count: number)
	for _ = 1, count do
		harness.mock:step()
	end
end

--[[
    A schema's inspector, required as PacketProfiler requires it, in a
    place whose ReplicatedStorage holds the scope's folder and its two
    remotes. Returns it, the scope's reliable remote and a remote outside
    the scope's folder
--]]

local function inspector(name: string, text: string): (any, any, any)
	local extra: { Extra } = select(4, Generated.modules(name, text))
	local game: any = roblox.Instance.new("DataModel")
	local storage: any = game:GetService("ReplicatedStorage")
	local volt: any = roblox.Instance.new("Folder")
	local scope: any = roblox.Instance.new("Folder")
	local reliable: any = roblox.Instance.new("RemoteEvent")
	local unreliable: any = roblox.Instance.new("UnreliableRemoteEvent")
	local outside: any = roblox.Instance.new("RemoteEvent")

	volt.Name, scope.Name, reliable.Name, unreliable.Name = Contract.folder, name, "Reliable", "Unreliable"
	volt.Parent, scope.Parent, reliable.Parent, unreliable.Parent, outside.Parent = storage, volt, scope, scope, storage

	local inspect: any = Generated.module("Inspector", extra[#extra].text, Volt.mock(task.spawn).server, nil, {
		game = game,
	})

	return inspect, reliable, outside
end

-- A value as a test reads it: an instance by its name, a table by its keys in order, anything else as itself
local function shown(value: any): string
	if typeof(value) == "Instance" then
		return value.Name
	elseif type(value) ~= "table" then
		return tostring(value)
	end

	local keys: { any } = {}
	local parts: { string } = {}

	for key: any in value do
		table.insert(keys, key)
	end

	table.sort(keys, function (a: any, b: any): boolean
		return tostring(a) < tostring(b)
	end)

	for _, key: any in keys do
		table.insert(parts, `{key}={shown(value[key])}`)
	end

	return `\{{table.concat(parts, " ")}}`
end

-- What the inspector answered for one packet: each message noted, its arguments in order, or nil
local function listed(calls: Calls): string
	if not calls then
		return "nil"
	end

	local lines: { string } = {}

	for _, call in calls do
		local last: number = 0
		local arguments: { string } = {}

		for index: number in call.Arguments do
			last = math.max(last, index)
		end

		for index: number = 1, last do
			arguments[index] = shown(call.Arguments[index])
		end

		table.insert(lines, `{call.Name}({table.concat(arguments, ", ")})`)
	end

	return table.concat(lines, "; ")
end

-- Every packet one side kept, each handed over as PacketProfiler hands it, a line a packet
local function read(inspect: any, remote: any, kept: { Kept }, player: any?): string
	local lines: { string } = {}

	for _, entry: Kept in kept do
		if player then
			table.insert(lines, listed(inspect(remote, player, entry.packet, entry.side)))
		else
			table.insert(lines, listed(inspect(remote, entry.packet, entry.side)))
		end
	end

	return table.concat(lines, "\n")
end

-- A schema of the test schemas, with an inspector, then a server and Alice's client of it and its inspector
local function inspected(name: string): (Harness, any, any)
	local text: string = `{INSPECTED}{fs.readFile(`tests/Schemas/{name}.volt`)}`
	local inspect: any, remote: any = inspector(name, text)

	return profiled(name, text), inspect, remote
end

describe("Packet inspector", function ()
	local inspect: any, remote: any, outside: any = inspector("Tooling", SCHEMA)
	local _, hash: number = Generated.compile("Tooling", SCHEMA)

	test("reads what a client sends: its handshake, then each message with its values", function ()
		local harness: Harness = profiled("Tooling", SCHEMA)

		harness.client.Post.fire({ name = "Ada", kind = "Warn" })

		task.spawn(function ()
			harness.client.Lookup.invoke("Bo")
		end)

		steps(harness, 1)

		expect(read(inspect, remote, harness.toServer, harness.alice)).is(
			`Volt handshake({hash}); Lookup (call)(Bo)\nPost(\{kind=Warn name=Ada})`
		)
	end)

	test("reads what the server sends: each message, an instance, and a reply refused and answered", function ()
		local harness: Harness = profiled("Tooling", SCHEMA)

		task.spawn(function ()
			harness.client.Lookup.invoke("Ada")
		end)

		steps(harness, 3)

		harness.server.Lookup.on(function (_, name: string): any
			return { name = name, kind = "Info" }
		end)

		task.spawn(function ()
			harness.client.Lookup.invoke("Bo")
		end)

		harness.server.Sync.fire(harness.alice, 7)
		harness.server.Seen.fire(harness.alice, roblox.Instance.new("Part"), { name = "Cy", kind = "Warn" })
		steps(harness, 3)

		expect(read(inspect, remote, harness.toClient)).is(table.concat({
			"Lookup (reply)(false, no handler)",
			"Sync(7); Seen(Part, {kind=Warn name=Cy})",
			"Lookup (reply)(true, {kind=Info name=Bo})",
		}, "\n"))
	end)

	test("answers nil for a remote outside its scope's folder", function ()
		local bytes: buffer = packet({ 1, 7 })

		expect(listed(inspect(outside, bytes, {}))).is("nil")
		expect(listed(inspect(remote, bytes, {}))).is("Sync(7)")
	end)

	test("ends a packet that fails with the messages before it and the failure, and never raises", function ()
		local alice: any = { Name = "Alice" }

		expect(listed(inspect(remote, alice, packet({ 1, 9, 2, 0, #NAME - 1 }), {}))).is(
			"Sync(9); decode: Post(Entry.name: length out of range)"
		)
		expect(listed(inspect(remote, alice, packet({ 1, 9, 9 }), {}))).is(
			"Sync(9); packet: unknown message 9(unknown message 9)"
		)
		expect(listed(inspect(remote, packet({ 3, 1, 0, 7 }), {}))).is("decode: Lookup(Lookup: unknown status 7)")
		expect(listed(inspect(remote, alice, 5, nil)):match("^packet: ") ~= nil).is(true)
	end)

	test("reads for display alone: no listener hears what it reads, and no count moves", function ()
		local harness: Harness = profiled("Tooling", SCHEMA)
		local heard: number = 0

		local function counted(): string
			local stats: Volt.Stats = harness.server.stats()
			return `{stats.packetsIn} {stats.bytesIn} {stats.messagesIn}`
		end

		harness.server.Post.on(function ()
			heard += 1
		end)

		harness.client.Post.fire({ name = "Ada", kind = "Warn" })
		steps(harness, 2)

		local before: string = counted()
		read(inspect, remote, harness.toServer, harness.alice)

		expect(`{heard} {counted()}`).is(`1 {before}`)
	end)

	test("finds its scope under the runtime's folder, and refuses each status the runtime refuses", function ()
		expect(Contract.folder).is(Runtime.folder)
		expect(Contract.statuses).is(Runtime.status.limited)
	end)

	describe("of each form", function ()
		test("reads the channel byte every packet opens with, and then a server packet's stamp", function ()
			local harness: Harness, streams: any, streamsRemote: any = inspected("Streams")
			local _, streamsHash: number = Generated.compile("Streams", fs.readFile("tests/Schemas/Streams.volt"))

			harness.mock.time = 12.5
			harness.client.Chat.fire("yo")
			harness.server.Notice.fire(harness.alice, 3)
			harness.server.Chat.fire(harness.alice, "hi")
			steps(harness, 2)

			expect(read(streams, streamsRemote, harness.toServer, harness.alice)).is(
				`Volt handshake({streamsHash})\nChat(yo)`
			)
			expect(read(streams, streamsRemote, harness.toClient)).is(
				"Volt stamp(12.5); Notice(3)\nVolt stamp(12.5); Chat(hi)"
			)
			expect(listed(streams(streamsRemote, packet({ 2 }), {}))).is("packet: unknown channel 2(unknown channel 2)")
		end)

		test("reads an ordered message's sequence ahead of its values", function ()
			local harness: Harness, ordered: any, orderedRemote: any = inspected("Ordered")
			local sequences: { string } = {}

			harness.client.Aim.fire(0, 0)
			harness.client.Aim.fire(0, 0)
			steps(harness, 1)

			for sequence: string in read(ordered, orderedRemote, harness.toServer, harness.alice):gmatch("Aim%((%d+),") do
				table.insert(sequences, sequence)
			end

			expect(table.concat(sequences, " ")).is("1 2")
		end)

		test("reads the dictionary message at id 0, and a dictionary string as the id it travels as", function ()
			local harness: Harness, dictionary: any, dictionaryRemote: any = inspected("Dictionary")

			harness.server.picked.fire(harness.alice, "Sword", "Scout")
			steps(harness, 2)

			expect(read(dictionary, dictionaryRemote, harness.toClient)).is(
				"Volt dictionary(1, Sword, Scout)\npicked(1, 2)"
			)
		end)

		test("reads an awaited instance as the id it travels as", function ()
			local harness: Harness, awaited: any, awaitedRemote: any = inspected("Awaited")

			harness.server.World.Spawned.fire(harness.alice, roblox.Instance.new("Model"), 5)
			steps(harness, 2)

			expect(read(awaited, awaitedRemote, harness.toClient)).is("World.Spawned(1, 5)")
		end)

		test("reads a @delta message's mask, then the fields it carries", function ()
			local harness: Harness, deltas: any, deltasRemote: any = inspected("Deltas")
			local gear: { [string]: boolean } = { shield = true, boots = false }

			harness.server.vitals.fire(harness.alice, { health = 1, stamina = 2, title = "t", gear = gear })
			steps(harness, 2)
			harness.server.vitals.fire(harness.alice, { health = 9, stamina = 2, title = "t", gear = gear })
			steps(harness, 1)

			expect(read(deltas, deltasRemote, harness.toClient)).is(
				"vitals(31, {gear={boots=false shield=true} health=1 stamina=2 title=t})\nvitals(1, {health=9})"
			)
		end)
	end)

	test("V4003 refuses an inspector whose module-level locals pass fileLocals, since it never shards", function ()
		local declarations: { string } = { `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"` }

		for index: number = 1, FILE_LOCALS do
			table.insert(declarations, `export type T{index} = u8`)
			table.insert(
				declarations,
				`event E{index} \{ from: Client, type: Reliable, call: ManySync, data: T{index} }`
			)
		end

		local file, schemaHash, diagnostics = Generated.compile("Big", `{INSPECTED}{table.concat(declarations, "\n")}`)
		local expected: string =
			"error V4003: the inspector needs 154 module-level locals, more than one generated file holds (150)"

		Targets.modules(file, diagnostics, schemaHash)

		expect(diagnostics.errors).is(1)
		expect(diagnostics:render():find(expected, 1, true) ~= nil).is(true)
	end)
end)
