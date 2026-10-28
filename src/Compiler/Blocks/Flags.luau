--[[
    The flag bytes of a block as text: the bytes and words a count of bits
    takes, the word and bit a claim of bits starts at, the expression a
    word is read back from on the read side, and the stores that write a
    word on the write side once every bit in it is set
--]]

--!strict
local Flags = {}

local WORD_BITS: number = 32 -- What one flags local holds, which is as far as bit32 reaches
local STORE_WIDTHS: { number } = { 4, 2, 1 } -- The buffer widths flag bytes are stored with, widest first

-- One store or read of a word: its width, the byte it starts at among the flag bytes and the bit it starts at in the word
type Store = { width: number, byte: number, shift: number }

--[[
    Every store or read that carries one word of a block's flag bytes: the
    width of each, the byte it starts at among the flag bytes and the bit
    it starts at within the word
--]]

local function stores(word: number, bytes: number): { Store }
	local list: { Store } = {}
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

-- The flag bytes a count of bits takes, and the words of the locals that build or hold them
function Flags.size(bits: number): (number, number)
	return math.ceil(bits / 8), math.ceil(bits / WORD_BITS)
end

--[[
    The word and the bit a claim of the next bits starts at, given how
    many bits were claimed before it, the word counted from one as the
    locals are
--]]

function Flags.claim(claimed: number, width: number, path: string): (number, number)
	local bit: number = claimed % WORD_BITS

	-- Whiteoak TODO: a tag that straddles two words is refused; split it over both when a block needs one
	assert(bit + width <= WORD_BITS, `{path}: a flag of {width} bits does not fit its word at bit {bit}`)

	return claimed // WORD_BITS + 1, bit
end

--[[
    The expression one word of the flag bytes is read back from, given
    where each byte of the flag bytes sits in the packet
--]]

function Flags.read(word: number, bytes: number, at: (number) -> string): string
	local parts: { string } = {}

	for _, store: Store in stores(word, bytes) do
		local read: string = `buffer.readu{store.width * 8}(packet, {at(store.byte)})`
		table.insert(parts, store.shift == 0 and read or `{read} * {2 ^ store.shift}`)
	end

	return table.concat(parts, " + ")
end

--[[
    The stores of one word of the flag bytes, one statement each, given
    the word's local, the bits the block holds, the buffer and where each
    byte of the flag bytes sits in it
--]]

function Flags.stored(name: string, word: number, bits: number, out: string, at: (number) -> string): { string }
	local statements: { string } = {}
	local wordBits: number = math.min(WORD_BITS, bits - word * WORD_BITS)

	for _, store: Store in stores(word, math.ceil(bits / 8)) do
		local whole: boolean = store.shift == 0 and wordBits <= store.width * 8
		local value: string = whole and name or `bit32.extract({name}, {store.shift}, {store.width * 8})`

		table.insert(statements, `buffer.writeu{store.width * 8}({out}, {at(store.byte)}, {value})`)
	end

	return statements
end

return Flags
