--[[
    The payloads the benchmark sends, one bench each: the two of Blink's
    published benchmark, a mixed struct and a small unreliable input. A
    bench says how often a frame it is fired and builds one payload from
    a random stream, so a pool built from the fixed seed is the same on
    both sides and the server knows the first payload the client sends
--]]

--!strict
export type Bench = {
	name: string,
	perFrame: number, -- Fires a frame, sized so a frame of them fits under Volt's outgoing cap
	unreliable: boolean?,
	build: (random: Random) -> any,
}

local SEED: number = 0
local ENTITIES: number = 100 -- Entities per payload, as Blink's benchmark sends
local BOOLEANS: number = 1000 -- Booleans per payload, as Blink's benchmark sends
local SNAPSHOTS: number = 50
local BYTE: number = 255
local EXTENT: number = 512 -- A position lies within this many studs of the origin
local TURN: number = 6283 -- A yaw is a multiple of a power of two below two pi, so it survives f32 exactly
local TURN_STEPS: number = 1024
local HEALTH: number = 100
local NAME_SHORTEST: number = 4
local NAME_LONGEST: number = 12
local LETTER_A: number = string.byte("a")
local LETTER_Z: number = string.byte("z")
local TARGET: number = 65535
local TARGET_ODDS: number = 3 -- One snapshot in this many has no target
local DIRECTIONS: number = 7

-- A random word of lowercase letters
local function word(random: Random): string
	local letters: { string } = {}

	for _ = 1, random:NextInteger(NAME_SHORTEST, NAME_LONGEST) do
		table.insert(letters, string.char(random:NextInteger(LETTER_A, LETTER_Z)))
	end

	return table.concat(letters)
end

local Benches = {}

Benches.list = {
	{
		name = "Entities",
		perFrame = 400,
		build = function (random: Random)
			local entities: { any } = table.create(ENTITIES)

			for index = 1, ENTITIES do
				entities[index] = {
					id = random:NextInteger(1, BYTE),
					x = random:NextInteger(1, BYTE),
					y = random:NextInteger(1, BYTE),
					z = random:NextInteger(1, BYTE),
					orientation = random:NextInteger(1, BYTE),
					animation = random:NextInteger(1, BYTE),
				}
			end

			return entities
		end,
	},
	{
		name = "Booleans",
		perFrame = 1000,
		build = function ()
			return table.create(BOOLEANS, true)
		end,
	},
	{
		name = "Snapshots",
		perFrame = 100,
		build = function (random: Random)
			local snapshots: { any } = table.create(SNAPSHOTS)

			for index = 1, SNAPSHOTS do
				snapshots[index] = {
					position = Vector3.new(
						random:NextInteger(-EXTENT, EXTENT),
						random:NextInteger(-EXTENT, EXTENT),
						random:NextInteger(-EXTENT, EXTENT)
					),
					yaw = random:NextInteger(0, TURN) / TURN_STEPS,
					health = random:NextInteger(0, HEALTH),
					name = word(random),
					target = random:NextInteger(1, TARGET_ODDS) > 1 and random:NextInteger(1, TARGET) or nil,
				}
			end

			return snapshots
		end,
	},
	{
		name = "Input",
		perFrame = 1000,
		unreliable = true,
		build = function (random: Random)
			return { dir = random:NextInteger(0, DIRECTIONS), jump = random:NextInteger(0, 1) == 1 }
		end,
	},
} :: { Bench }

-- A pool of payloads from the fixed seed, the same on both sides
function Benches.pool(bench: Bench, count: number): { any }
	local random: Random = Random.new(SEED)
	local pool: { any } = table.create(count)

	for index = 1, count do
		pool[index] = bench.build(random)
	end

	return pool
end

return Benches
