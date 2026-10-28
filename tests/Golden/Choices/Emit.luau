local beginReliable, allocateReliable, slotReliable, refuseReliable = ...

export type Team = "Red" | "Blue"
export type Loadout = { perks: { [number]: true }, team: Team }

local TEAM: { "Red" | "Blue" } = { "Red", "Blue" }

local VARIANTS: { "Join" | "Leave" } = { "Join", "Leave" }

local MATERIAL: { [number]: Enum.Material } = {}
for _, item: Enum.Material in Enum.Material:GetEnumItems() do
	MATERIAL[item.Value] = item
end

local function writeTeam(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(1)
	local flags: number = 0
	local valueIndex: number = table.find(TEAM, value) or 0

	if valueIndex == 0 then
		refuse("Team: expected enum { Red, Blue }")
	end

	flags += valueIndex - 1
	buffer.writeu8(out, offset, flags)
end

local function readTeam(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Team)
	if cursor + 1 > length then
		error("Team: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local value: ("Red" | "Blue")? = TEAM[bit32.extract(flags, 0, 1) + 1]

	if not value then
		error("Team: out of range")
	end

	cursor += 1

	return cursor, sideCursor, value
end

local function writeLoadout(allocate: (number) -> (number, buffer), slot: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(1)

	if type(value) ~= "table" then
		refuse("Loadout: expected table")
	end

	local perks = value.perks

	if type(perks) ~= "table" then
		refuse("Loadout.perks: expected table")
	end

	local perksCount: number = 0

	for _ in perks do
		perksCount += 1
	end

	if perksCount > 2 then
		refuse("Loadout.perks: length out of range")
	end

	buffer.writeu8(out, offset, perksCount)
	local perksOffset: number, perksOut: buffer = allocate(perksCount)

	for perksKey in perks do
		if type(perksKey) ~= "number" or bit32.band(perksKey, 255) ~= perksKey then
			refuse("Loadout.perks[]: expected u8")
		end

		buffer.writeu8(perksOut, perksOffset, perksKey)
		perksOffset += 1
	end

	writeTeam(allocate, slot, refuse, value.team)
end

local function readLoadout(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number): (number, number, Loadout)
	if cursor + 1 > length then
		error("Loadout: truncated")
	end

	local perksLength: number = buffer.readu8(packet, cursor)

	if perksLength > 2 then
		error("Loadout.perks: length out of range")
	end

	local team: Team
	cursor += 1

	if cursor + perksLength > length then
		error("Loadout.perks: truncated")
	end

	local perks: { [number]: true } = {}

	for _ = 1, perksLength do
		local perksKey: number = buffer.readu8(packet, cursor)
		cursor += 1

		if perks[perksKey] ~= nil then
			error("Loadout.perks: duplicate key")
		end

		perks[perksKey] = true
	end

	cursor, sideCursor, team = readTeam(packet, cursor, side, sideCursor, length)
	local value = { perks = perks, team = team }

	return cursor, sideCursor, value
end

local function writeVariants(value: { kind: "Join", team: Team, perks: { [number]: true }, floor: Enum.Material, loadout: Loadout } | { kind: "Leave" })
	local offset: number, out: buffer = beginReliable(1)
	local flags: number = 0

	if type(value) ~= "table" then
		refuseReliable("Variants: expected table")
	end

	local valueIndex: number = table.find(VARIANTS, value.kind) or 0

	if valueIndex == 0 then
		refuseReliable("Variants: expected enum \"kind\" { Join { team: Team, perks: set<u8>(0..2), floor: Enum.Material, loadout: Loadout }, Leave }")
	end

	flags += valueIndex - 1
	buffer.writeu8(out, offset, flags)

	if valueIndex == 1 then
		local offset_2: number, out_2: buffer = allocateReliable(3)
		local valueJoin = value :: { kind: "Join", team: Team, perks: { [number]: true }, floor: Enum.Material, loadout: Loadout }
		local perks = valueJoin.perks

		if type(perks) ~= "table" then
			refuseReliable("Variants.perks: expected table")
		end

		local perksCount: number = 0

		for _ in perks do
			perksCount += 1
		end

		if perksCount > 2 then
			refuseReliable("Variants.perks: length out of range")
		end

		buffer.writeu8(out_2, offset_2, perksCount)
		local floor = valueJoin.floor

		if typeof(floor) ~= "EnumItem" or floor.EnumType ~= Enum.Material then
			refuseReliable("Variants.floor: expected Enum.Material")
		end

		buffer.writeu16(out_2, offset_2 + 1, floor.Value)
		writeTeam(allocateReliable, slotReliable, refuseReliable, valueJoin.team)
		local perksOffset: number, perksOut: buffer = allocateReliable(perksCount)

		for perksKey in perks do
			if type(perksKey) ~= "number" or bit32.band(perksKey, 255) ~= perksKey then
				refuseReliable("Variants.perks[]: expected u8")
			end

			buffer.writeu8(perksOut, perksOffset, perksKey)
			perksOffset += 1
		end

		writeLoadout(allocateReliable, slotReliable, refuseReliable, valueJoin.loadout)
	end
end

local function readVariants(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	if cursor + 1 > length then
		error("Variants: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local valueTag: number = bit32.extract(flags, 0, 1)
	local value: { kind: "Join", team: Team, perks: { [number]: true }, floor: Enum.Material, loadout: Loadout } | { kind: "Leave" }
	cursor += 1

	if valueTag == 0 then
		if cursor + 3 > length then
			error("Variants: truncated")
		end

		local team: Team
		local perksLength: number = buffer.readu8(packet, cursor)

		if perksLength > 2 then
			error("Variants.perks: length out of range")
		end

		local floor: Enum.Material? = MATERIAL[buffer.readu16(packet, cursor + 1)]

		if not floor then
			error("Variants.floor: out of range")
		end

		local loadout: Loadout
		cursor += 3
		cursor, sideCursor, team = readTeam(packet, cursor, side, sideCursor, length)

		if cursor + perksLength > length then
			error("Variants.perks: truncated")
		end

		local perks: { [number]: true } = {}

		for _ = 1, perksLength do
			local perksKey: number = buffer.readu8(packet, cursor)
			cursor += 1

			if perks[perksKey] ~= nil then
				error("Variants.perks: duplicate key")
			end

			perks[perksKey] = true
		end

		cursor, sideCursor, loadout = readLoadout(packet, cursor, side, sideCursor, length)
		value = { kind = "Join", team = team, perks = perks, floor = floor, loadout = loadout }
	elseif valueTag == 1 then
		value = { kind = "Leave" }
	else
		error("Variants: out of range")
	end

	return cursor, sideCursor, value
end

local function writeMembers(value: number | { team: Team, perks: { [number]: true }, floor: Enum.Material, loadout: Loadout })
	local offset: number, out: buffer = beginReliable(1)
	local flags: number = 0
	local valueMember: number = typeof(value) == "number" and 0 or typeof(value) == "table" and 1 or -1

	if valueMember < 0 then
		refuseReliable("Members: expected u8 | struct { team: Team, perks: set<u8>(0..2), floor: Enum.Material, loadout: Loadout }")
	end

	flags += valueMember
	buffer.writeu8(out, offset, flags)

	if valueMember == 0 then
		local offset_2: number, out_2: buffer = allocateReliable(1)
		local value_2 = (value :: number)

		if bit32.band(value_2, 255) ~= value_2 then
			refuseReliable("Members: expected u8")
		end

		buffer.writeu8(out_2, offset_2, value_2)
	elseif valueMember == 1 then
		local offset_3: number, out_3: buffer = allocateReliable(3)
		local value_3 = (value :: { team: Team, perks: { [number]: true }, floor: Enum.Material, loadout: Loadout })
		local perks = value_3.perks

		if type(perks) ~= "table" then
			refuseReliable("Members.perks: expected table")
		end

		local perksCount: number = 0

		for _ in perks do
			perksCount += 1
		end

		if perksCount > 2 then
			refuseReliable("Members.perks: length out of range")
		end

		buffer.writeu8(out_3, offset_3, perksCount)
		local floor = value_3.floor

		if typeof(floor) ~= "EnumItem" or floor.EnumType ~= Enum.Material then
			refuseReliable("Members.floor: expected Enum.Material")
		end

		buffer.writeu16(out_3, offset_3 + 1, floor.Value)
		writeTeam(allocateReliable, slotReliable, refuseReliable, value_3.team)
		local perksOffset: number, perksOut: buffer = allocateReliable(perksCount)

		for perksKey in perks do
			if type(perksKey) ~= "number" or bit32.band(perksKey, 255) ~= perksKey then
				refuseReliable("Members.perks[]: expected u8")
			end

			buffer.writeu8(perksOut, perksOffset, perksKey)
			perksOffset += 1
		end

		writeLoadout(allocateReliable, slotReliable, refuseReliable, value_3.loadout)
	end
end

local function readMembers(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	if cursor + 1 > length then
		error("Members: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local valueTag: number = bit32.extract(flags, 0, 1)
	local value: number | { team: Team, perks: { [number]: true }, floor: Enum.Material, loadout: Loadout }
	cursor += 1

	if valueTag == 0 then
		if cursor + 1 > length then
			error("Members: truncated")
		end

		local value_2: number = buffer.readu8(packet, cursor)
		cursor += 1
		value = value_2 :: number
	elseif valueTag == 1 then
		if cursor + 3 > length then
			error("Members: truncated")
		end

		local team: Team
		local perksLength: number = buffer.readu8(packet, cursor)

		if perksLength > 2 then
			error("Members.perks: length out of range")
		end

		local floor: Enum.Material? = MATERIAL[buffer.readu16(packet, cursor + 1)]

		if not floor then
			error("Members.floor: out of range")
		end

		local loadout: Loadout
		cursor += 3
		cursor, sideCursor, team = readTeam(packet, cursor, side, sideCursor, length)

		if cursor + perksLength > length then
			error("Members.perks: truncated")
		end

		local perks: { [number]: true } = {}

		for _ = 1, perksLength do
			local perksKey: number = buffer.readu8(packet, cursor)
			cursor += 1

			if perks[perksKey] ~= nil then
				error("Members.perks: duplicate key")
			end

			perks[perksKey] = true
		end

		cursor, sideCursor, loadout = readLoadout(packet, cursor, side, sideCursor, length)
		local value_3 = { team = team, perks = perks, floor = floor, loadout = loadout }
		value = value_3 :: { team: Team, perks: { [number]: true }, floor: Enum.Material, loadout: Loadout }
	else
		error("Members: out of range")
	end

	return cursor, sideCursor, value
end

return {
	Variants = { write = writeVariants, read = readVariants },
	Members = { write = writeMembers, read = readMembers },
}
