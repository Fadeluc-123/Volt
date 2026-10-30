--[[
    Proves profileLabels over Tooling.volt's modules, each run with a
    recording debug: a reader's label opens first and closes once its
    tail returns, whichever tail it is, the flush is labelled, a failed
    decode leaves nothing open, and a sharded build labels as one file
    does; without the option nothing is labelled, under the same hash
--]]

--!strict
local fs = require("@lune/fs")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes it provides
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local golden = require("./Expected")
local packet = require("./Packet")
local profiled = require("./Profiled")
local TargetsTypes = require("@volt/Compiler/Config/Types/Targets")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Extra = TargetsTypes.Extra
type Harness = profiled.Harness
type Labels = profiled.Labels

local SCHEMA: string = fs.readFile("tests/Schemas/Tooling.volt")
local PLAIN: string = (SCHEMA:gsub("option profileLabels[^\n]*\n", ""):gsub("option inspectorOutput[^\n]*\n", ""))
local SHARDED: string = `option shardSize = 1\n{SCHEMA}`
local LABELLED: string = "option profileLabels = true\n" -- Put before another schema's text, so its modules label
local CLIENT: string, SERVER: string, _: string, EXTRA: { Extra } = Generated.modules("Tooling", SCHEMA)
local NAME: string = string.rep("n", 17) -- One byte past the 16 Entry.name holds

-- Steps the mock, every label each side opened closed again by the end of the step
local function steps(harness: Harness, count: number)
	for _ = 1, count do
		harness.mock:step()
		expect(#harness.labels.server.open + #harness.labels.client.open).is(0)
	end
end

-- A side's log since it was last read, as one line, starting the next one empty
local function logged(labels: Labels): string
	local line: string = table.concat(labels.log, ",")
	table.clear(labels.log)
	return line
end

-- How many times a run of labels was logged by a side since it was last read
local function times(labels: Labels, run: string): number
	local pattern: string = run:gsub("%p", "%%%0")
	local _, count: number = logged(labels):gsub(pattern, "")
	return count
end

-- Whether a text holds another word for word
local function holds(text: string, part: string): boolean
	return text:find(part, 1, true) ~= nil
end

-- The server's log of the step that reads a client's Post, after the step that sends it with the handshake
local function posted(text: string): string
	local harness: Harness = profiled("Tooling", text)

	harness.client.Post.fire({ name = "Ada", kind = "Warn" })
	steps(harness, 1)
	logged(harness.labels.server)
	steps(harness, 1)

	return logged(harness.labels.server)
end

describe("Profile labels", function ()
	test("renders the modules and the inspector as their golden files", function ()
		expect(golden("tests/Golden/Tooling", "Client", CLIENT)).is(CLIENT)
		expect(golden("tests/Golden/Tooling", "Server", SERVER)).is(SERVER)
		expect(EXTRA[1].output).is("Inspector.luau")
		expect(golden("tests/Golden/Tooling", "Inspector", EXTRA[1].text)).is(EXTRA[1].text)
	end)

	test("hashes the same with its build options or without, and unlabelled carries no label", function ()
		local _, hash: number = Generated.compile("Tooling", SCHEMA)
		local _, plainHash: number = Generated.compile("Tooling", PLAIN)
		local client: string, server: string, _: string, extra: { Extra } = Generated.modules("Tooling", PLAIN)

		expect(hash).is(plainHash)
		expect(#extra).is(0)
		expect(holds(SERVER, "\tprofiler = debug,")).is(true)
		expect(`{holds(client, "debug")} {holds(server, "debug")}`).is("false false")
	end)

	test("reads a client's Post inside the server's receive label and its own, each closed", function ()
		expect(posted(SCHEMA)).is(
			"Volt Tooling receive,end,Volt Tooling receive,Volt Tooling Post,end,end,Volt Tooling flush,end"
		)
	end)

	test("closes the reply reader's label for a Lookup refused with no handler and for one answered", function ()
		local harness: Harness = profiled("Tooling", SCHEMA)
		local results: { string } = {}

		local function ask(name: string)
			task.spawn(function ()
				local ok: boolean, entry: any = harness.client.Lookup.invoke(name)
				table.insert(results, `{ok} {type(entry) == "table" and entry.name or entry}`)
			end)
		end

		ask("Ada")
		steps(harness, 3)
		harness.server.Lookup.on(function (_, name: string): any
			return { name = name, kind = "Info" }
		end)
		ask("Bo")
		steps(harness, 3)

		expect(table.concat(results, ",")).is("false no handler,true Bo")
		expect(times(harness.labels.client, "Volt Tooling receive,Volt Tooling Lookup,end,end")).is(2)
	end)

	test(
		"reports a Post that fails its check with the detail an unlabelled module reports, its label closed",
		function ()
			local details: { string } = {}

			for _, text: string in { SCHEMA, PLAIN } do
				local harness: Harness = profiled("Tooling", text)

				harness.server.onFailure(function (_, kind: string, detail: string)
					table.insert(details, `{kind} {detail}`)
				end)

				steps(harness, 2)
				harness.transport.unreliable(nil, packet({ 2, 0, #NAME - 1 }))
				steps(harness, 1)
			end

			expect(details[1]).is("decode Post: Entry.name: length out of range")
			expect(details[2]).is(details[1])
		end
	)

	test("labels the flush a game calls itself", function ()
		local harness: Harness = profiled("Tooling", SCHEMA)

		harness.server.flush()
		harness.client.flush()

		expect(logged(harness.labels.server)).is("Volt Tooling flush,end")
		expect(logged(harness.labels.client)).is("Volt Tooling flush,end")
	end)

	describe("closes every tail's label", function ()
		test("an ordered event's, on each side", function ()
			local harness: Harness = profiled("Ordered", `{LABELLED}{fs.readFile("tests/Schemas/Ordered.volt")}`)

			-- Past the handshake, since an unreliable message for a player not yet handshaken is dropped
			steps(harness, 2)
			harness.client.Aim.fire(0, 0)
			harness.server.Aim.fire(harness.alice, 0, 0)
			steps(harness, 2)

			expect(times(harness.labels.server, "Volt Ordered Aim,end")).is(1)
			expect(times(harness.labels.client, "Volt Ordered Aim,end")).is(1)
		end)

		test("an awaited event's, which waits for nothing here", function ()
			local harness: Harness = profiled("Awaited", `{LABELLED}{fs.readFile("tests/Schemas/Awaited.volt")}`)

			harness.server.World.Spawned.fire(harness.alice, roblox.Instance.new("Model"), 5)
			steps(harness, 3)

			expect(times(harness.labels.client, "Volt Awaited World.Spawned,end")).is(1)
		end)

		test("a @delta event's, whose merge is read inside the deliver it closes after", function ()
			local harness: Harness = profiled("Deltas", `{LABELLED}{fs.readFile("tests/Schemas/Deltas.volt")}`)
			local vitals: { [string]: any } =
				{ health = 1, stamina = 2, title = "t", gear = { shield = true, boots = false } }

			harness.server.vitals.fire(harness.alice, vitals)
			steps(harness, 3)

			expect(times(harness.labels.client, "Volt Deltas vitals,end")).is(1)
		end)

		test("a server's call to a client, and its reply as answered and as refused", function ()
			local harness: Harness = profiled("Prompts", `{LABELLED}{fs.readFile("tests/Schemas/Prompts.volt")}`)
			local results: { string } = {}

			harness.client.Confirm.on(function (): (boolean, string?)
				return true, nil
			end)

			task.spawn(function ()
				local ok: boolean = harness.server.Confirm.invoke(harness.alice, "Go?", 1)
				local poked: boolean = harness.server.Poke.invoke(harness.alice)
				table.insert(results, `{ok} {poked}`)
			end)

			steps(harness, 6)

			expect(table.concat(results, ",")).is("true false")
			expect(times(harness.labels.client, "Volt Prompts Confirm,end")).is(1)

			local server: string = logged(harness.labels.server)
			expect(`{holds(server, "Volt Prompts Confirm,end")} {holds(server, "Volt Prompts Poke,end")}`).is(
				"true true"
			)
		end)
	end)

	test("labels a sharded build as one file, its entry handing the runtime the profiler", function ()
		local server: string, _: string, extra: { Extra } = select(2, Generated.modules("Tooling", SHARDED))
		local inspector: Extra = table.remove(extra) :: Extra
		local shards: string = ""

		for _, file: Extra in extra do
			shards = `{shards}{file.text}`
		end

		expect(`{#extra} {inspector.output}`).is("8 Inspector.luau")
		expect(inspector.text).is(EXTRA[1].text)
		expect(holds(server, "\tprofiler = debug,")).is(true)
		expect(holds(shards, `debug.profilebegin("Volt Tooling Post")`)).is(true)
		expect(posted(SHARDED)).is(posted(SCHEMA))
	end)
end)
