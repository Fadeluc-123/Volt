--[[
    Proves the names the assembly guards: a top-level name the API owns is
    refused in the schema's casing, the one a handshake failure opens with
    in any, and a type the modules declare or name always; and a module
    keeps a helper only when its code names it, never a string's text
--]]

--!strict
local fs = require("@lune/fs")

local Suite = require("./Suite")
local Generated = require("./Generated")
local Targets = require("@volt/Compiler/Targets")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

local EVENTS: string = fs.readFile("tests/Schemas/Events.volt")

-- How many errors assembling a schema text's modules reports, and what it rendered
local function refused(text: string): (number, string)
	local file, hash, diagnostics = Generated.compile("Bad", text)

	Targets.modules(file, diagnostics, hash)

	return diagnostics.errors, diagnostics:render()
end

describe("Names", function ()
	test("refuses a top-level name the API owns, in the schema's casing", function ()
		-- The casing, then the name a declaration may not take in it
		local cases: { { string } } = { { "pascal", "OnFailure" }, { "camel", "version" }, { "pascal", "Version" } }

		for _, case: { string } in cases do
			local declaration: string = `event {case[2]} \{ from: Client, type: Reliable, call: SingleSync }`
			local errors: number, rendered: string = refused(`option casing = {case[1]}\n{EVENTS}\n{declaration}`)
			local expected: string = `error V4001: "{case[2]}" is a member of the generated API`

			expect(errors).is(1)
			expect(rendered:find(expected, 1, true) ~= nil).is(true)
		end
	end)

	test("refuses the name a handshake failure's detail opens with, whatever the casing", function ()
		local declaration: string = "event Volt { from: Client, type: Reliable, call: SingleSync }"
		local errors: number, rendered: string = refused(`{EVENTS}\n{declaration}`)

		expect(errors).is(1)
		expect(rendered:find(`error V4001: "Volt" opens a handshake failure's detail`, 1, true) ~= nil).is(true)
	end)

	test("refuses a type the modules declare or name, which the namespaced one never collides with", function ()
		for _, name: string in { "Bot", "Player" } do
			local errors: number, rendered: string =
				refused(`{EVENTS}\ntype {name} = u8\nnamespace Arena \{ type {name} = u8 }`)
			local expected: string = `error V4002: "{name}" is a type the generated modules declare or name`

			expect(errors).is(1)
			expect(rendered:find(expected, 1, true) ~= nil).is(true)
		end
	end)

	test("keeps a helper on the side whose code calls it, not one whose refusal names it", function ()
		local declaration: string =
			"event cframe { from: Client, type: Reliable, call: SingleSync, data: (at: CFrame) }"
		local client: string, server: string = Generated.modules("Names", `{EVENTS}\n{declaration}`)

		expect((client:find("local function cframe(", 1, true))).is(nil)
		expect(server:find("local function cframe(", 1, true) ~= nil).is(true)
	end)
end)
