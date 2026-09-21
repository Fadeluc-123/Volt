--[[
    What a generated chunk sees as globals under Lune: the Roblox
    datatypes @lune/roblox provides, and the DateTime it lacks as a
    stand-in with the two members the generated code touches and a
    typeof that reports it
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes it provides

-- Lune has no Roblox DateTime, so the tests carry one with the two members the generated code touches
local Stamp: { [string]: any } = {}
local DateTime = {
	fromUnixTimestamp = function (seconds: number)
		return setmetatable({ UnixTimestamp = seconds, UnixTimestampMillis = seconds * 1000 }, Stamp)
	end,

	fromUnixTimestampMillis = function (millis: number)
		return setmetatable({ UnixTimestamp = millis / 1000, UnixTimestampMillis = millis }, Stamp)
	end,
}

local Environment: { [string]: any } = {
	BrickColor = roblox.BrickColor,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	DateTime = DateTime,
	Enum = roblox.Enum,
	Instance = roblox.Instance,
	Vector2 = roblox.Vector2,
	Vector3 = roblox.Vector3,

	typeof = function (value: any): string
		return getmetatable(value) == Stamp and "DateTime" or typeof(value)
	end,
}

return Environment
