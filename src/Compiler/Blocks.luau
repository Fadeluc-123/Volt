--[[
    The blocks the generator writes serialisers in. A block is a straight
    line region whose byte size is known at compile time, so a writer
    allocates it once and a reader bounds-checks it once, and every field
    sits at a constant offset. A block owns its flag bytes and a tail that
    carries the variable-size payloads and child blocks after its bytes
--]]

--!strict
local Blocks = {} :: any
Blocks.__index = Blocks

export type Side = "write" | "read"

export type Block = {
	side: Side,
	path: string,
	out: string,
	reserve: (self: Block, bytes: number) -> number,
	at: (self: Block, index: number) -> string,
	flags: (self: Block, bits: number) -> (),
	flag: (self: Block, count: number?) -> (string, number),
	name: (self: Block, hint: string) -> string,
	line: (self: Block, text: string) -> (),
	tail: (self: Block, text: string) -> (),
	extend: (self: Block, hint: string, path: string, bytes: string, payload: (string, string) -> string) -> (),
	child: (self: Block, path: string?) -> Block,
	done: (self: Block) -> string,
}

-- Names the generated code reaches for that no local may shadow
local RESERVED: { string } = {
	"allocate",
	"bit32",
	"buffer",
	"cursor",
	"deliver",
	"error",
	"length",
	"math",
	"net",
	"packet",
	"player",
	"readf16",
	"side",
	"sideCursor",
	"string",
	"table",
	"tostring",
	"typeof",
	"writef16",
}

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

local function append(list: { string }, indent: number, text: string)
	for line: string in text:gmatch("[^\n]+") do
		table.insert(list, `{string.rep("\t", indent)}{line}`)
	end
end

--[[
    A root block for one generated function, or with a parent a child of
    it: an optional payload, a variant body or a loop iteration whose
    lines land in the parent's tail once it is done
--]]

function Blocks.new(side: Side, path: string, allocate: string?, parent: Block?): Block
	local names: { [string]: boolean } = parent and (parent :: any)._names or {}

	if not parent then
		for _, name: string in RESERVED do
			names[name] = true
		end
	end

	local self = setmetatable({
		side = side,
		path = path,
		out = "packet", -- The buffer the fixed bytes are read from, or written to once allocated
		_parent = parent,
		_indent = parent and (parent :: any)._indent + 1 or 1,
		_allocate = allocate or "allocate", -- What the write side calls for its bytes
		_offset = "cursor", -- Where the fixed bytes start
		_bytes = 0, -- Fixed bytes reserved so far
		_bits = 0, -- Flag bits the block was opened with
		_claimed = 0, -- Flag bits handed out so far
		_flagsAt = 0, -- Where the flag bytes sit among the fixed bytes
		_words = {} :: { string }, -- The flags locals, one per 32 bits
		_body = {} :: { string },
		_tail = {} :: { string },
		_names = names, -- Every local the function holds, so no two collide
	}, Blocks)

	if side == "write" then
		self._offset = self:name("offset")
		self.out = self:name("out")
	end

	return self :: any
end

--[[
    Opens a child block. The caller writes the lines that open and close
    the scope around it into this block's tail
--]]

function Blocks:child(path: string?): Block
	return Blocks.new(self.side, path or self.path, self._allocate, self)
end

--[[
    Reserves fixed bytes at the next constant offset and returns that
    offset, which at() renders as an expression
--]]

function Blocks:reserve(bytes: number): number
	local index: number = self._bytes
	self._bytes += bytes
	return index
end

function Blocks:at(index: number): string
	return index == 0 and self._offset or `{self._offset} + {index}`
end

--[[
    Reserves the flag bytes for the bits the block will claim, at the
    point in the fixed bytes the walk has reached, and opens the locals
    that build them on the write side and hold them on the read side
--]]

function Blocks:flags(bits: number)
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

function Blocks:flag(count: number?): (string, number)
	local width: number = count or 1
	local index: number = self._claimed
	local bit: number = index % WORD_BITS

	-- Whiteoak TODO: a tag that straddles two words is refused; split it over both when a block needs one
	assert(bit + width <= WORD_BITS, `{self.path}: a flag of {width} bits does not fit its word at bit {bit}`)
	self._claimed += width

	return self._words[index // WORD_BITS + 1], bit
end

--[[
    A local name from a hint, unique within the function the root block
    becomes, so a field name never collides with another or with what the
    generated code already uses
--]]

function Blocks:name(hint: string): string
	local names: { [string]: boolean } = self._names
	local candidate: string = hint
	local suffix: number = 1

	while names[candidate] do
		suffix += 1
		candidate = `{hint}_{suffix}`
	end

	names[candidate] = true
	return candidate
end

-- A line among the fixed bytes, at a constant offset
function Blocks:line(text: string)
	append(self._body, self._indent, text)
end

-- A line after the fixed bytes, where the variable payloads and child blocks go
function Blocks:tail(text: string)
	append(self._tail, self._indent, text)
end

--[[
    A variable-size payload after the fixed bytes: the write side takes
    it from the allocator into locals named for the field, the read side
    checks it is all there and steps the cursor past it. The payload
    callback writes the line between, given the buffer and offset to use
--]]

function Blocks:extend(hint: string, path: string, bytes: string, payload: (string, string) -> string)
	if self.side == "write" then
		local offset: string = self:name(`{hint}Offset`)
		local out: string = self:name(`{hint}Out`)

		self:tail(`local {offset}: number, {out}: buffer = {self._allocate}({bytes})`)
		self:tail(payload(out, offset))
		return
	end

	self:tail(`if cursor + {bytes} > length then\n\terror("{path}: truncated")\nend`)
	self:tail(payload("packet", "cursor"))
	self:tail(`cursor += {bytes}`)
end

--[[
    Closes the block: one allocation or bounds check for its fixed bytes
    at the top, the flag bytes stored after those bytes are written on
    the write side and the cursor stepped past them on the read side,
    then the tail. A child's lines land in its parent's tail
--]]

function Blocks:done(): string
	assert(self._claimed == self._bits, `{self.path}: {self._claimed} flag bits claimed of {self._bits} reserved`)

	local lines: { string } = {}
	local bytes: number = self._bytes

	if bytes > 0 and self.side == "write" then
		append(lines, self._indent, `local {self._offset}: number, {self.out}: buffer = {self._allocate}({bytes})`)
	elseif bytes > 0 then
		append(lines, self._indent, `if cursor + {bytes} > length then\n\terror("{self.path}: truncated")\nend`)
	end

	table.move(self._body, 1, #self._body, #lines + 1, lines)

	if self.side == "write" then
		local flagBytes: number = math.ceil(self._bits / 8)

		for word: number, name: string in self._words do
			local wordBits: number = math.min(WORD_BITS, self._bits - (word - 1) * WORD_BITS)

			for _, store in stores(word - 1, flagBytes) do
				local whole: boolean = store.shift == 0 and wordBits <= store.width * 8
				local value: string = whole and name or `bit32.extract({name}, {store.shift}, {store.width * 8})`
				local at: string = self:at(self._flagsAt + store.byte)

				append(lines, self._indent, `buffer.writeu{store.width * 8}({self.out}, {at}, {value})`)
			end
		end
	elseif bytes > 0 then
		append(lines, self._indent, `cursor += {bytes}`)
	end

	table.move(self._tail, 1, #self._tail, #lines + 1, lines)

	if self._parent then
		table.move(lines, 1, #lines, #self._parent._tail + 1, self._parent._tail)
	end

	return #lines == 0 and "" or `{table.concat(lines, "\n")}\n`
end

return Blocks
