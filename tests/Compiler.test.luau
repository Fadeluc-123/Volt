--[[
    Proves the volt command checks a schema and exits with the right code,
    prints the resolved declarations on --ast, and prints nothing but the
    diagnostics on --quiet
--]]

--!strict
local process = require("@lune/process")

local Suite = require("./Suite")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

local EXAMPLE: string = "tests/Schemas/Example.volt"

local function volt(...: string): process.ExecResult
	return process.exec("lune", { "run", "src/Compiler", ... })
end

describe("Compiler", function ()
	test("checks the example, reports its hash and exits 0", function ()
		local result: process.ExecResult = volt(EXAMPLE, "--check")

		expect(result.code).is(0)
		expect(result.stderr).is("")
		expect(result.stdout:match("^tests/Schemas/Example.volt: ok, schema hash 0x%x+\n$") ~= nil).is(true)
	end)

	test("--ast prints the resolved declarations and --quiet drops the summary", function ()
		local result: process.ExecResult = volt(EXAMPLE, "--ast", "--quiet")
		local line: string = "type Reference = string(1..64) -- 2..65 bytes, 2 references"

		expect(result.code).is(0)
		expect(result.stdout:find(line, 1, true) ~= nil).is(true)
		expect((result.stdout:find("schema hash", 1, true))).is(nil)
	end)

	test("exits 2 without a schema and 1 with diagnostics on a file that is not one", function ()
		local usage: process.ExecResult = volt()
		local broken: process.ExecResult = volt("stylua.toml")

		expect(usage.code).is(2)
		expect(usage.stderr:sub(1, 6)).is("usage:")
		expect(broken.code).is(1)
		expect(broken.stderr:find("error V", 1, true) ~= nil).is(true)
	end)
end)
