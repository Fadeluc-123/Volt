--[[
    The flag bytes, merged onto the blocks: where they sit among a block's
    fixed bytes, the locals that build them on the write side and read
    them on the read side, the bits handed out of those locals, and the
    stores that write them once every bit is set
--]]

--!strict
local Flags = {} :: any

local WORD_BITS: number = 32 -- What one flags local holds, which is as far as bit32 reaches
local STORE_WIDTHS: { number } = { 4, 2, 1 } -- The buffer widths flag bytes are stored with, widest first

--[[
    Every store or read that carries one word of a block's flag bytes: the
    width of each, the byte it starts at among the flag bytes and the bit
    it starts at within the word
--]]

local function stores(word: number, bytes: number): { { width: number, byte: number, shift: number } }
	local list: { { width: number, byte: number, shift: number } } = {}
	local byte: number = word * 4
	local remaining: number = math.min(4, bytes - byte)

	for _, width: number in STORE_WIDTHS do
		while remaining >= width do
			table.insert(list, { width = width, byte = byte, shift = (byte - word * 4) * 8 })
			byte += width
			remaining -= width
		end
	end

	return list
end

--[[
    Reserves the flag bytes for the bits the block will claim, at the
    point in the fixed bytes the walk has reached, and opens the locals
    that build them on the write side and hold them on the read side
--]]

function Flags:flags(bits: number)
	local bytes: number = math.ceil(bits / 8)

	self._bits = bits
	self._flagsAt = self:reserve(bytes)

	for word: number = 0, math.ceil(bits / WORD_BITS) - 1 do
		local name: string = self:name("flags")
		table.insert(self._words, name)

		if self.side == "write" then
			self:line(`local {name}: number = 0`)
			continue
		end

		local parts: { string } = {}
		for _, store in stores(word, bytes) do
			local read: string = `buffer.readu{store.width * 8}(packet, {self:at(self._flagsAt + store.byte)})`
			table.insert(parts, store.shift == 0 and read or `{read} * {2 ^ store.shift}`)
		end

		self:line(`local {name}: number = {table.concat(parts, " + ")}`)
	end
end

--[[
    Claims the next flag bits, returning the local that holds them and
    the bit they start at
--]]

function Flags:flag(count: number?): (string, number)
	local width: number = count or 1
	local index: number = self._claimed
	local bit: number = index % WORD_BITS

	-- Whiteoak TODO: a tag that straddles two words is refused; split it over both when a block needs one
	assert(bit + width <= WORD_BITS, `{self.path}: a flag of {width} bits does not fit its word at bit {bit}`)
	self._claimed += width

	return self._words[index // WORD_BITS + 1], bit
end

-- The write side's stores of the flag bytes, one statement each, which go after the fixed bytes once every bit is set
function Flags:_stored(): { string }
	local statements: { string } = {}
	local flagBytes: number = math.ceil(self._bits / 8)

	for word: number, name: string in self._words do
		local wordBits: number = math.min(WORD_BITS, self._bits - (word - 1) * WORD_BITS)

		for _, store in stores(word - 1, flagBytes) do
			local whole: boolean = store.shift == 0 and wordBits <= store.width * 8
			local value: string = whole and name or `bit32.extract({name}, {store.shift}, {store.width * 8})`
			local at: string = self:at(self._flagsAt + store.byte)

			table.insert(statements, `buffer.writeu{store.width * 8}({self.out}, {at}, {value})`)
		end
	end

	return statements
end

return Flags
