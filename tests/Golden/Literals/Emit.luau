local beginReliable, trimReliable, allocateReliable, slotReliable, refuseReliable = ...

export type Hit = { kind: "melee", damage: number, version: number, critical: boolean, ranked: true }

local function writeHit(allocate: (number) -> (number, buffer), _: (any) -> (), refuse: (string) -> never, value: any)
	local offset: number, out: buffer = allocate(3)
	local flags: number = 0

	if type(value) ~= "table" then
		refuse("Hit: expected table")
	end

	if value.kind ~= "melee" then
		refuse("Hit.kind: expected \"melee\"")
	end

	local damage = value.damage

	if type(damage) ~= "number" or bit32.band(damage, 65535) ~= damage then
		refuse("Hit.damage: expected u16")
	end

	buffer.writeu16(out, offset + 1, damage)

	if value.version ~= 2 then
		refuse("Hit.version: expected 2")
	end

	local critical = value.critical

	if type(critical) ~= "boolean" then
		refuse("Hit.critical: expected boolean")
	end

	flags += critical and 1 or 0

	if value.ranked ~= true then
		refuse("Hit.ranked: expected true")
	end

	buffer.writeu8(out, offset, flags)
end

local function readHit(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number, Hit)
	if cursor + 3 > length then
		error("Hit: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local damage: number = buffer.readu16(packet, cursor + 1)
	cursor += 3
	local value: { kind: "melee", damage: number, version: number, critical: boolean, ranked: true } = { kind = "melee", damage = damage, version = 2, critical = bit32.btest(flags, 1), ranked = true }

	return cursor, sideCursor, value
end

local function writeHits(first: Hit, second: Hit)
	writeHit(allocateReliable, slotReliable, refuseReliable, first)
	writeHit(allocateReliable, slotReliable, refuseReliable, second)
end

local function readHits(packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number)
	local first: Hit
	local second: Hit
	cursor, sideCursor, first = readHit(packet, cursor, side, sideCursor, length)
	cursor, sideCursor, second = readHit(packet, cursor, side, sideCursor, length)

	return cursor, sideCursor, first, second
end

local function writeChoices(tag: "melee"?, reason: number | "none")
	local offset: number, out: buffer = beginReliable(2)
	local flags: number = 0
	flags += tag ~= nil and 1 or 0
	local reasonMember: number = typeof(reason) == "number" and 0 or typeof(reason) == "string" and 1 or -1

	if reasonMember < 0 then
		refuseReliable("Choices.reason: expected u8 | \"none\"")
	end

	flags += reasonMember * 2
	buffer.writeu8(out, offset, flags)
	offset += 1

	if tag ~= nil then
		if tag ~= "melee" then
			refuseReliable("Choices.tag: expected \"melee\"")
		end
	end

	if reasonMember == 0 then
		local reason_2 = (reason :: number)

		if bit32.band(reason_2, 255) ~= reason_2 then
			refuseReliable("Choices.reason: expected u8")
		end

		buffer.writeu8(out, offset, reason_2)
		offset += 1
	elseif reasonMember == 1 then
		if (reason :: "none") ~= "none" then
			refuseReliable("Choices.reason: expected \"none\"")
		end
	end

	trimReliable(offset)
end

local function readChoices(packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number)
	if cursor + 1 > length then
		error("Choices: truncated")
	end

	local flags: number = buffer.readu8(packet, cursor)
	local tag: "melee"?
	local reasonTag: number = bit32.extract(flags, 1, 1)
	local reason: number | "none"
	cursor += 1

	if bit32.btest(flags, 1) then
		tag = "melee"
	end

	if reasonTag == 0 then
		if cursor + 1 > length then
			error("Choices.reason: truncated")
		end

		local reason_2: number = buffer.readu8(packet, cursor)
		cursor += 1
		reason = reason_2 :: number
	elseif reasonTag == 1 then
		reason = "none" :: "none"
	else
		error("Choices.reason: out of range")
	end

	return cursor, sideCursor, tag, reason
end

return {
	Hits = { write = writeHits, read = readHits },
	Choices = { write = writeChoices, read = readChoices },
}
