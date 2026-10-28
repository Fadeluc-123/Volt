--[[
    Runs every tests/*.test.luau under tiniest in one report and exits
    non-zero when any test fails. An optional argument keeps only the files
    whose name contains it; flags such as --update are left for the tests
    themselves to read from process.args
--]]

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")

local Suite = require("../tests/Suite")

local filter: string? = nil

for _, argument: string in process.args do
	if argument:sub(1, 2) ~= "--" then
		filter = argument
	end
end

-- Requiring a test file registers its describes on the shared instance
local ok, tests = pcall(Suite.collect_tests, function ()
	for _, name: string in fs.readDir("tests") do
		local isTest: boolean = name:match("%.test%.luau$") ~= nil
		local isWanted: boolean = filter == nil or name:find(filter, 1, true) ~= nil

		if isTest and isWanted then
			(require :: any)(`../tests/{(name:gsub("%.luau$", ""))}`)
		end
	end
end)

if not ok then
	local report = tests :: any

	print(typeof(report) == "table" and `{report.source}:{report.line}: {report.message}` or tostring(report))
	process.exit(1)
end

local result = Suite.run_tests(tests, {})

process.exit(result.status_tally.fail > 0 and 1 or 0)
