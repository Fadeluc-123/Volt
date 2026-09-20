--[[
    The one configured tiniest instance. The runner collects tests through
    it and every test file registers its describes on it, so the whole
    suite lands in one run and one report
--]]

--!strict
local TiniestForLune = require("./tiniest/tiniest_for_lune")

return TiniestForLune.configure({})
