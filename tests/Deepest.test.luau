--[[
    Proves the deepest value @depth allows on Lune's stack: an exported
    Chain at the most depth writes and reads back every one of its levels
    and refuses one more, which the Studio smoke place proves again on the
    engine's stack, in native code
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local Generated = require("./Generated")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

-- The two options every schema must carry, so a fragment compiles clean
local HEADER: string = `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"\n`
local DEEPEST: number = 1000 -- The most levels @depth allows
local BYTE: number = 256 -- Level n holds n % BYTE, so the levels run through every u8 in turn
local SCHEMA: string = `{HEADER}@depth({DEEPEST}) export struct Chain \{ value: u8, next: Chain? }`

-- A chain of some levels, level n holding n % BYTE, built from the deepest up
local function chain(levels: number): { [string]: any }?
	local head: { [string]: any }? = nil

	for level: number = levels, 1, -1 do
		head = { value = level % BYTE, next = head }
	end

	return head
end

describe("Deepest", function ()
	test("an exported Chain writes and reads back a thousand levels, and refuses one more", function ()
		local client: string, server: string = Generated.modules("Deepest", SCHEMA)
		local mock: Volt.Mock = Volt.mock(task.spawn)
		local _, transport: Volt.Transport = mock:join("Alice")
		local writer: any = Generated.module("Client", client, transport)
		local reader: any = Generated.module("Server", server, mock.server)
		local bytes: buffer, side: { any }? = writer.exports.Chain.write(chain(DEEPEST))
		local link: { [string]: any }? = reader.exports.Chain.read(bytes, side)

		-- Each level with its number, so a wrong or missing one names where it is
		for level: number = 1, DEEPEST do
			expect(`{level} {link and link.value}`).is(`{level} {level % BYTE}`)
			link = link and link.next
		end

		expect(link).is(nil)

		local ok: boolean, message: any = pcall(writer.exports.Chain.write, chain(DEEPEST + 1))

		expect(ok).is(false)
		expect(tostring(message)).is("Chain: nested deeper than 1000")
	end)
end)
