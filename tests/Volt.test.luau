--[[
    Proves the package root loads through the volt alias, the require path
    every test uses to reach the runtime
--]]

--!strict
local Suite = require("./Suite")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

describe("Volt", function ()
	test("loads through the volt alias", function ()
		expect(require("@volt")).is_a("table")
	end)
end)
