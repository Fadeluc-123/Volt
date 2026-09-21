--[[
    A stand-in for the promise library a generated client requires when a
    function yields a promise: the one member the runtime touches, new,
    whose executor's resolve and reject keep what they were called with
    as settled, for a test to read
--]]

--!strict
local Promise = {}

export type Promise = { settled: { n: number, [number]: any }? } -- Whether it resolved, then the returns or the reason

function Promise.new(executor: (resolve: (...any) -> (), reject: (reason: any) -> ()) -> ()): Promise
	local self: Promise = { settled = nil }

	executor(function (...: any)
		self.settled = table.pack(true, ...)
	end, function (reason: any)
		self.settled = table.pack(false, reason)
	end)

	return self
end

return Promise
