--[[
    Steps a mock until one of its flushes runs more than the seconds given
    after the call, which a deadline the runtime checks at each flush
    needs, since its clock moves on its own and no test yields to wait
--]]

--!strict
local Volt = require("@volt")

type Mock = Volt.Mock

return function (mock: Mock, seconds: number)
	local deadline: number = os.clock() + seconds

	while os.clock() <= deadline do
		mock:step()
	end

	-- Every step above began on or before the deadline, so this one's flush is the first sure to run past it
	mock:step()
end
