--[[
    Proves the emitter's literals past what every family's round trips
    show: a fire carries only the bytes of the fields around them, a
    writer built without validation reads nothing of one, and a literal
    holding a backslash is spelled escaped in the generated code
--]]

--!strict
local fs = require("@lune/fs")

local Suite = require("./Suite")
local Families = require("./Families")
local Generated = require("./Generated")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

local HIT_BYTES: number = 3 -- A Hit's flag byte and its u16 damage, its literals taking none
local CHOICE_BYTES: number = 1 -- The flag byte the optional literal's presence and the union's tag share
local WRONG: string = "ranged" -- A value no literal here holds, which only a writer that checks refuses
local PATH: string = "C:\\Volt" -- A literal holding a backslash
local SLASHED: string = "C:/Volt" -- A value that is not that literal

-- A schema whose one event carries the literal holding a backslash
local ESCAPED: string = table.concat({
	`option clientOutput = "Client.luau"`,
	`option serverOutput = "Server.luau"`,
	`event Path \{ from: Client, type: Reliable, call: SingleSync, data: "C:\\Volt" }`,
}, "\n")

-- A Hit as written, every literal field holding its own value
local function hit(damage: number): { [string]: any }
	return { kind = "melee", damage = damage, version = 2, critical = true, ranked = true }
end

-- What a chunk's event read back from the packet its writer just made, after the two cursors
local function readBack(module: any, packet: () -> (buffer, { any }), name: string): (number, { any })
	local bytes: buffer, side: { any } = packet()
	local read: { any } = { module[name].read(bytes, 0, side, 1, buffer.len(bytes)) }

	return buffer.len(bytes), { table.unpack(read, 3) }
end

describe("Literals", function ()
	test("a fire carries only the bytes of the fields around its literals", function ()
		local module: any, packet: () -> (buffer, { any }) = Generated.load("Literals", Families.texts.Literals)

		module.Hits.write(hit(1), hit(2))

		local hitBytes: number, hits: { any } = readBack(module, packet, "Hits")

		module.Choices.write("melee", "none")

		local choiceBytes: number, choices: { any } = readBack(module, packet, "Choices")

		expect(hitBytes).is(2 * HIT_BYTES)
		expect(`{hits[2].kind} {hits[2].damage} {hits[2].version} {hits[2].ranked}`).is("melee 2 2 true")
		expect(choiceBytes).is(CHOICE_BYTES)
		expect(`{choices[1]} {choices[2]}`).is("melee none")
	end)

	test("a writer built without validation reads nothing of a literal and refuses no other value", function ()
		local source: string = `option writeValidation = false\n{fs.readFile("tests/Schemas/Literals.volt")}`
		local text: string = Generated.render((Generated.compile("Literals", source)))
		local module: any, packet: () -> (buffer, { any }) = Generated.load("Literals", text)
		local looked: { string } = {}
		local fields: { [string]: any } = { kind = WRONG, damage = 5, version = 3, critical = true, ranked = false }

		-- A hit that keeps every field the writer reads of it
		local watched: { [string]: any } = setmetatable({}, {
			__index = function (_, key: string): any
				table.insert(looked, key)
				return fields[key]
			end,
		})

		module.Hits.write(watched, watched)

		local _, hits: { any } = readBack(module, packet, "Hits")

		module.Choices.write(WRONG, WRONG)

		local _, choices: { any } = readBack(module, packet, "Choices")

		expect(table.concat(looked, ",")).is("damage,critical,damage,critical")
		expect(`{hits[1].kind} {hits[1].version} {hits[1].ranked}`).is("melee 2 true")
		expect(`{choices[1]} {choices[2]}`).is("melee none")
	end)

	test("a literal holding a backslash is spelled escaped, as a value and in its refusal", function ()
		local text: string = Generated.render((Generated.compile("Path", ESCAPED)))
		local module: any, packet: () -> (buffer, { any }) = Generated.load("Path", text)
		local ok: boolean, message: any = pcall(module.Path.write, SLASHED)

		expect(ok).is(false)
		expect(message).is(`Path: expected "{PATH}"`)

		module.Path.write(PATH)

		local bytes: number, read: { any } = readBack(module, packet, "Path")

		expect(bytes).is(0)
		expect(read[1]).is(PATH)
	end)
end)
