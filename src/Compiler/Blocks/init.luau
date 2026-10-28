--[[
    The blocks the generator writes serialisers in. A block is a straight
    line region whose byte size is known at compile time, so a writer
    allocates it once and a reader bounds-checks it once, and every field
    sits at a constant offset, with a tail for the variable-size payloads
    and child blocks after its bytes; its flag bytes are a sibling's
--]]

--!strict
local Blocks = {}
Blocks.__index = Blocks

-- An init file stands for its folder, so its siblings are reached through the folder's name
local Flags = require("./Blocks/Flags")
local Reserved = require("./Config/Reserved")

export type Side = "write" | "read"

-- A run of bytes a parent took from the allocator or checked once, for its children to fill
export type Region = { offset: string, out: string }

type Fields = {
	side: Side,
	path: string,
	out: string,
	first: string?,
	allocate: string,
	slot: string,
	refuse: string,
	_parent: Self?,
	_indent: number,
	_offset: string,
	_region: boolean,
	_held: number?,
	_running: string?,
	_bytes: number,
	_bits: number,
	_claimed: number,
	_flagsAt: number,
	_words: { string },
	_body: { string },
	_tail: { string },
	_groups: { { string } },
	_names: { [string]: boolean },
}

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

function Blocks.new(side: Side, path: string, parent: Self?, region: Region?): Self
	local names: { [string]: boolean } = parent and parent._names or {}

	if not parent then
		for _, name: string in Reserved.generated do
			names[name] = true
		end
	end

	local self: Self = setmetatable({
		side = side,
		path = path,
		out = region and region.out or "packet", -- The buffer the fixed bytes are read from, or written to once allocated
		first = nil :: string?, -- What a message's writer calls for its first bytes, which begins the message; nil takes them from allocate
		allocate = parent and parent.allocate or "allocate", -- What the write side calls for its bytes
		slot = parent and parent.slot or "slot", -- What the write side calls to store a side-array value
		refuse = parent and parent.refuse or "refuse", -- What the write side calls to refuse a value and undo the message
		_parent = parent,
		_indent = parent and parent._indent + 1 or 1,
		_offset = region and region.offset or "cursor", -- Where the fixed bytes start
		_region = region ~= nil, -- Whether the parent took or checked the fixed bytes already
		_held = nil :: number?, -- What a root's first call takes when it holds the writer's largest size
		_running = parent and parent._running, -- The offset every block writes at in turn once the root holds
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

	return self
end

--[[
    Opens a child block. The caller opens and closes the scope around it
    in this block's tail. Under a root that holds, a child takes its bytes
    at the running offset, as if its parent had taken them as a region
--]]

function Blocks.child(self: Self, path: string?, region: Region?): Self
	local running: string? = self._running
	return Blocks.new(self.side, path or self.path, self, region or running and { offset = running, out = self.out })
end

--[[
    Makes a message's writer take its largest size with its first call,
    so every region, payload and child after takes its bytes at a running
    offset rather than from the allocator. Returns the local the offset is
    in, which the writer trims with last to hand back what it did not use
--]]

function Blocks.hold(self: Self, bytes: number): string
	self._held = bytes
	self._running = self._offset
	return self._offset
end

--[[
    Reserves fixed bytes at the next constant offset and returns that
    offset, which at() renders as an expression
--]]

function Blocks.reserve(self: Self, bytes: number): number
	local index: number = self._bytes
	self._bytes += bytes
	return index
end

function Blocks.at(self: Self, index: number): string
	return index == 0 and self._offset or `{self._offset} + {index}`
end

--[[
    Reserves the flag bytes for the bits the block will claim, at the
    point in the fixed bytes the walk has reached, and opens the locals
    that build them on the write side and hold them on the read side
--]]

function Blocks.flags(self: Self, bits: number)
	local bytes: number, words: number = Flags.size(bits)

	self._bits = bits
	self._flagsAt = self:reserve(bytes)

	for word: number = 0, words - 1 do
		local name: string = self:name("flags")
		local value: string = self.side == "write" and "0" or Flags.read(word, bytes, self:_flagOffset())

		table.insert(self._words, name)
		self:line(`local {name}: number = {value}`)
	end
end

--[[
    Claims the next flag bits, returning the local that holds them and
    the bit they start at
--]]

function Blocks.flag(self: Self, count: number?): (string, number)
	local width: number = count or 1
	local word: number, bit: number = Flags.claim(self._claimed, width, self.path)

	self._claimed += width

	return self._words[word], bit
end

-- Where a byte of the flag bytes sits, as an expression, for the reads and stores spelled from them
function Blocks._flagOffset(self: Self): (number) -> string
	return function (byte: number): string
		return self:at(self._flagsAt + byte)
	end
end

--[[
    A local name from a hint, unique within the function the root block
    becomes, so a field name never collides with another or with what the
    generated code already uses
--]]

function Blocks.name(self: Self, hint: string): string
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
function Blocks.empty(self: Self): boolean
	return self._bytes == 0 and self._bits == 0 and #self._body == 0 and #self._tail == 0
end

-- The list a tail statement lands in: the innermost open scope, or the tail itself
function Blocks._target(self: Self): { string }
	return self._groups[#self._groups] or self._tail
end

-- A statement among the fixed bytes, at a constant offset
function Blocks.line(self: Self, text: string)
	table.insert(self._body, Blocks.indent(self._indent, text))
end

-- A statement after the fixed bytes, where the variable payloads and child blocks go
function Blocks.tail(self: Self, text: string)
	table.insert(self:_target(), Blocks.indent(self._indent, text))
end

--[[
    Opens a scope in the tail, a branch or a loop, that closes as one
    statement: everything that lands in the tail until the close, a child
    block's lines included, is part of it and stays packed together
--]]

function Blocks.open(self: Self, text: string)
	table.insert(self._groups, { Blocks.indent(self._indent, text) })
end

function Blocks.close(self: Self, text: string)
	local group: { string }? = table.remove(self._groups)
	assert(group, `{self.path}: closing a scope when none is open`)

	table.insert(group, Blocks.indent(self._indent, text))
	table.insert(self:_target(), table.concat(group, "\n"))
end

--[[
    Takes a run of bytes after the fixed bytes: the write side from the
    allocator into locals named for the field, or at the running offset
    under a root that holds, the read side checked to be all there. What
    fills it, a payload or a loop of child blocks over it, comes next
--]]

function Blocks.region(self: Self, hint: string, path: string, bytes: string): Region
	if self._running then
		return {
			offset = self._running,
			out = self.out,
		}
	elseif self.side == "write" then
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
    the buffer and offset to use; the read side's cursor and a held
    writer's running offset step past it
--]]

function Blocks.extend(self: Self, hint: string, path: string, bytes: string, payload: (string, string) -> string)
	local region: Region = self:region(hint, path, bytes)
	self:tail(payload(region.out, region.offset))

	if self.side == "read" or self._running then
		self:tail(`{region.offset} += {bytes}`)
	end
end

--[[
    Closes the block: one allocation or bounds check for its fixed bytes
    at the top unless a region holds them, the flag bytes stored after
    those bytes are written on the write side and the offset or cursor
    stepped past them, then the tail, then the final statement as a
    paragraph of its own. A child's text lands in its parent's tail
--]]

function Blocks.done(self: Self, final: string?): string
	assert(self._claimed == self._bits, `{self.path}: {self._claimed} flag bits claimed of {self._bits} reserved`)
	assert(#self._groups == 0, `{self.path}: a scope was left open`)

	local statements: { string } = {}
	local bytes: number = self._bytes
	local taken: number = self._held or bytes -- A root that holds takes the writer's largest size, not its fixed bytes

	-- A region's bytes were taken or checked by the parent, so only a block of its own opens with a line
	if taken > 0 and not self._region and self.side == "write" then
		self:line(`local {self._offset}: number, {self.out}: buffer = {self.first or self.allocate}({taken})`)
		table.insert(statements, table.remove(self._body) :: string)
	elseif bytes > 0 and not self._region then
		self:line(`if cursor + {bytes} > length then\n\terror("{self.path}: truncated")\nend`)
		table.insert(statements, table.remove(self._body) :: string)
	end

	table.move(self._body, 1, #self._body, #statements + 1, statements)

	if self.side == "write" then
		for word: number, name: string in self._words do
			for _, store: string in Flags.stored(name, word - 1, self._bits, self.out, self:_flagOffset()) do
				table.insert(statements, Blocks.indent(self._indent, store))
			end
		end

		-- The running offset steps past the fixed bytes, whether a region's or a holding root's, for the tail after
		if bytes > 0 and (self._region or self._held ~= nil) then
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

	local parent: Self? = self._parent
	if parent and text ~= "" then
		table.insert(parent:_target(), text)
	end

	return text == "" and "" or `{text}\n`
end

export type Block = Self
type Self = typeof(setmetatable({} :: Fields, Blocks))

return Blocks
