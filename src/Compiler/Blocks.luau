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

local Reserved = require("./Config/Reserved")

export type Side = "write" | "read"

-- A run of bytes a parent took from the allocator or checked once, for its children to fill
export type Region = { offset: string, out: string }

export type Block = {
	side: Side,
	path: string,
	out: string,
	allocate: string,
	slot: string,
	reserve: (self: Block, bytes: number) -> number,
	at: (self: Block, index: number) -> string,
	flags: (self: Block, bits: number) -> (),
	flag: (self: Block, count: number?) -> (string, number),
	name: (self: Block, hint: string) -> string,
	empty: (self: Block) -> boolean,
	line: (self: Block, text: string) -> (),
	tail: (self: Block, text: string) -> (),
	open: (self: Block, text: string) -> (),
	close: (self: Block, text: string) -> (),
	region: (self: Block, hint: string, path: string, bytes: string) -> Region,
	extend: (self: Block, hint: string, path: string, bytes: string, payload: (string, string) -> string) -> (),
	child: (self: Block, path: string?, region: Region?) -> Block,
	done: (self: Block, final: string?) -> string,
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

-- A statement's lines each indented by the level, with a blank line left blank
function Blocks.indent(level: number, text: string): string
	return (text:gsub("[^\n]+", `{string.rep("\t", level)}%0`))
end

--[[
    Statements one per line, with a blank line on either side of any that
    spans several lines, so a check or a branch stands apart from the
    straight-line writes around it
--]]

function Blocks.paragraphs(statements: { string }): string
	local parts: { string } = {}
	local spanned: boolean = false -- Whether the statement before spans several lines

	for index: number, statement: string in statements do
		local spans: boolean = statement:find("\n") ~= nil

		if index > 1 then
			table.insert(parts, (spans or spanned) and "\n\n" or "\n")
		end

		table.insert(parts, statement)
		spanned = spans
	end

	return table.concat(parts)
end

--[[
    A root block for one generated function, or with a parent a child of
    it: an optional payload, a variant body or a loop iteration whose
    lines land in the parent's tail once it is done. A child opened over a
    region fills bytes its parent already took or checked
--]]

function Blocks.new(side: Side, path: string, parent: Block?, region: Region?): Block
	local names: { [string]: boolean } = parent and (parent :: any)._names or {}

	if not parent then
		for _, name: string in Reserved.generated do
			names[name] = true
		end
	end

	local self = setmetatable({
		side = side,
		path = path,
		out = region and region.out or "packet", -- The buffer the fixed bytes are read from, or written to once allocated
		allocate = parent and parent.allocate or "allocate", -- What the write side calls for its bytes
		slot = parent and parent.slot or "slot", -- What the write side calls to store a side-array value
		_parent = parent,
		_indent = parent and (parent :: any)._indent + 1 or 1,
		_offset = region and region.offset or "cursor", -- Where the fixed bytes start
		_region = region ~= nil, -- Whether the parent took or checked the fixed bytes already
		_bytes = 0, -- Fixed bytes reserved so far
		_bits = 0, -- Flag bits the block was opened with
		_claimed = 0, -- Flag bits handed out so far
		_flagsAt = 0, -- Where the flag bytes sit among the fixed bytes
		_words = {} :: { string }, -- The flags locals, one per 32 bits
		_body = {} :: { string }, -- The statements among the fixed bytes
		_tail = {} :: { string }, -- The statements after them
		_groups = {} :: { { string } }, -- The scopes open in the tail, innermost last, each gathering one statement
		_names = names, -- Every local the function holds, so no two collide
	}, Blocks)

	if side == "write" and not region then
		self._offset = self:name("offset")
		self.out = self:name("out")
	end

	return self :: any
end

--[[
    Opens a child block. The caller opens and closes the scope around it
    in this block's tail
--]]

function Blocks:child(path: string?, region: Region?): Block
	return Blocks.new(self.side, path or self.path, self, region)
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

-- Whether nothing was reserved or written into the block, so a branch around it would be empty
function Blocks:empty(): boolean
	return self._bytes == 0 and self._bits == 0 and #self._body == 0 and #self._tail == 0
end

-- The list a tail statement lands in: the innermost open scope, or the tail itself
function Blocks:_target(): { string }
	return self._groups[#self._groups] or self._tail
end

-- A statement among the fixed bytes, at a constant offset
function Blocks:line(text: string)
	table.insert(self._body, Blocks.indent(self._indent, text))
end

-- A statement after the fixed bytes, where the variable payloads and child blocks go
function Blocks:tail(text: string)
	table.insert(self:_target(), Blocks.indent(self._indent, text))
end

--[[
    Opens a scope in the tail, a branch or a loop, that closes as one
    statement: everything that lands in the tail until the close, a child
    block's lines included, is part of it and stays packed together
--]]

function Blocks:open(text: string)
	table.insert(self._groups, { Blocks.indent(self._indent, text) })
end

function Blocks:close(text: string)
	local group: { string }? = table.remove(self._groups)
	assert(group, `{self.path}: closing a scope when none is open`)

	table.insert(group, Blocks.indent(self._indent, text))
	table.insert(self:_target(), table.concat(group, "\n"))
end

--[[
    Takes a run of bytes after the fixed bytes: the write side from the
    allocator into locals named for the field, the read side checked to
    be all there. What fills it, a payload or a loop of child blocks over
    the region, comes next in the tail
--]]

function Blocks:region(hint: string, path: string, bytes: string): Region
	if self.side == "write" then
		local offset: string = self:name(`{hint}Offset`)
		local out: string = self:name(`{hint}Out`)

		self:tail(`local {offset}: number, {out}: buffer = {self.allocate}({bytes})`)

		return {
			offset = offset,
			out = out,
		}
	end

	self:tail(`if cursor + {bytes} > length then\n\terror("{path}: truncated")\nend`)

	return {
		offset = "cursor",
		out = "packet",
	}
end

--[[
    A variable-size payload after the fixed bytes, taken as a region and
    filled by the payload callback, which writes the line between given
    the buffer and offset to use; the read side steps the cursor past it
--]]

function Blocks:extend(hint: string, path: string, bytes: string, payload: (string, string) -> string)
	local region: Region = self:region(hint, path, bytes)
	self:tail(payload(region.out, region.offset))

	if self.side == "read" then
		self:tail(`cursor += {bytes}`)
	end
end

--[[
    Closes the block: one allocation or bounds check for its fixed bytes
    at the top unless a region holds them, the flag bytes stored after
    those bytes are written on the write side and the offset or cursor
    stepped past them, then the tail, then the final statement as a
    paragraph of its own. A child's text lands in its parent's tail
--]]

function Blocks:done(final: string?): string
	assert(self._claimed == self._bits, `{self.path}: {self._claimed} flag bits claimed of {self._bits} reserved`)
	assert(#self._groups == 0, `{self.path}: a scope was left open`)

	local statements: { string } = {}
	local bytes: number = self._bytes

	-- A region's bytes were taken or checked by the parent, so only a block of its own opens with a line
	if bytes > 0 and not self._region and self.side == "write" then
		self:line(`local {self._offset}: number, {self.out}: buffer = {self.allocate}({bytes})`)
		table.insert(statements, table.remove(self._body) :: string)
	elseif bytes > 0 and not self._region then
		self:line(`if cursor + {bytes} > length then\n\terror("{self.path}: truncated")\nend`)
		table.insert(statements, table.remove(self._body) :: string)
	end

	table.move(self._body, 1, #self._body, #statements + 1, statements)

	if self.side == "write" then
		local flagBytes: number = math.ceil(self._bits / 8)

		for word: number, name: string in self._words do
			local wordBits: number = math.min(WORD_BITS, self._bits - (word - 1) * WORD_BITS)

			for _, store in stores(word - 1, flagBytes) do
				local whole: boolean = store.shift == 0 and wordBits <= store.width * 8
				local value: string = whole and name or `bit32.extract({name}, {store.shift}, {store.width * 8})`
				local at: string = self:at(self._flagsAt + store.byte)

				table.insert(
					statements,
					Blocks.indent(self._indent, `buffer.writeu{store.width * 8}({self.out}, {at}, {value})`)
				)
			end
		end

		if bytes > 0 and self._region then
			table.insert(statements, Blocks.indent(self._indent, `{self._offset} += {bytes}`))
		end
	elseif bytes > 0 then
		table.insert(statements, Blocks.indent(self._indent, `cursor += {bytes}`))
	end

	table.move(self._tail, 1, #self._tail, #statements + 1, statements)

	local text: string = Blocks.paragraphs(statements)
	if final then
		text = `{text == "" and "" or `{text}\n\n`}{Blocks.indent(self._indent, final)}`
	end

	if self._parent and text ~= "" then
		table.insert(self._parent:_target(), text)
	end

	return text == "" and "" or `{text}\n`
end

return Blocks
