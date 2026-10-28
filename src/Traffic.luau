--[[
    One player's byte count, shared by every runtime of a VM: the bytes
    sent to them, kept in slices of the last second so the sum moves as
    time does, and their send states, whose cursors are what was written
    for them and not yet flushed
--]]

--!strict
local Config = require("./Config/Runtime")
local Types = require("./Config/Types/Runtime")

type Record = Types.Record

local SLICES: number = Config.trafficSlices
local WIDTH: number = Config.trafficSeconds / Config.trafficSlices -- The seconds one slice covers

local Traffic = {}

--[[
    Hands out one record per player, made the first time it is asked for
    one and let go with the player, since the keys are weak. A hub keeps
    one for every runtime it serves, and a runtime on a transport without
    a hub keeps its own
--]]

function Traffic.records(): (player: any) -> Record
	local records: { [any]: Record } = setmetatable({}, { __mode = "k" }) :: any

	return function (player: any): Record
		local record: Record? = records[player]
		if record then
			return record
		end

		local made: Record = { slices = table.create(SLICES, 0), stamps = table.create(SLICES, 0), states = {} }
		records[player] = made

		return made
	end
end

-- Adds a packet's bytes to the slice of the moment it left, starting the slice over when it last counted a second ago
function Traffic.add(record: Record, bytes: number)
	local stamp: number = os.clock() // WIDTH
	local index: number = stamp % SLICES + 1

	if record.stamps[index] ~= stamp then
		record.stamps[index] = stamp
		record.slices[index] = 0
	end

	record.slices[index] += bytes
end

-- The bytes sent over the last second, then the bytes written and not yet flushed, held ones included
function Traffic.read(record: Record): (number, number)
	local stamp: number = os.clock() // WIDTH
	local stamps: { number } = record.stamps
	local sent: number, pending: number = 0, 0

	for index: number, bytes: number in record.slices do
		if stamp - stamps[index] < SLICES then
			sent += bytes
		end
	end

	for state: any in record.states do
		pending += state.cursor
	end

	return sent, pending
end

return Traffic
