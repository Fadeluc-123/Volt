--[[
    Checks every resolved type against the wire rules, gives each message
    an id per direction, sizes types in bytes and flag bits, refuses an
    unreliable event that cannot fit one fire, and prints the canonical
    form of a file that --ast shows and the schema hash is taken over
--]]

--!strict
local Analyse = {} :: any
Analyse.__index = Analyse

local Diagnostics = require("./Diagnostics")
local Parser = require("./Parser")

type Declaration = Parser.Declaration
type Diagnostics = Diagnostics.Diagnostics
type Event = Parser.Event
type Field = Parser.Field
type File = Parser.File
type Pack = Parser.Pack
type Range = Parser.Range
type Roblox = Parser.Roblox
type Spec = Parser.Spec
type Type = Parser.Type
type TypeDeclaration = Parser.TypeDeclaration
type Variant = Parser.Variant

export type Size = { min: number, max: number, bits: number, slots: number }

local BYTES: { [string]: number } = {
	u8 = 1,
	u16 = 2,
	u24 = 3,
	u32 = 4,
	u48 = 6,
	u64 = 8,
	i8 = 1,
	i16 = 2,
	i24 = 3,
	i32 = 4,
	i48 = 6,
	i64 = 8,
	f16 = 2,
	f32 = 4,
	f64 = 8,
	q8 = 1,
	q16 = 2,
}

-- The 64-bit integers stop where a Luau number stops being exact
local BOUNDS: { [string]: { number } } = {
	u8 = { 0, 255 },
	u16 = { 0, 65535 },
	u24 = { 0, 2 ^ 24 - 1 },
	u32 = { 0, 2 ^ 32 - 1 },
	u48 = { 0, 2 ^ 48 - 1 },
	u64 = { 0, 2 ^ 53 },
	i8 = { -128, 127 },
	i16 = { -32768, 32767 },
	i24 = { -2 ^ 23, 2 ^ 23 - 1 },
	i32 = { -2 ^ 31, 2 ^ 31 - 1 },
	i48 = { -2 ^ 47, 2 ^ 47 - 1 },
	i64 = { -2 ^ 53, 2 ^ 53 },
}

local ROBLOX_BYTES: { [string]: number } = { Color3 = 3, BrickColor = 2, DateTime = 8, DateTimeMillis = 8, Enum = 2 }
local GENERICS: { [string]: number } = { Vector3 = 1, Vector2 = 1, CFrame = 2, AlignedCFrame = 1 }
local INSTANCES: { [string]: boolean } = { Instance = true, StreamedInstance = true }
local COUNTS: { string } = { "one", "two" }

-- How each runtime class reads in an ambiguity message
local CLASSES: { [string]: string } = {
	number = "numbers",
	string = "strings",
	buffer = "buffers",
	boolean = "booleans",
	struct = "tables with named fields",
	list = "arrays or maps",
	Instance = "instances",
}

local DEFAULT_COMPONENT: Size = { min = 4, max = 4, bits = 0, slots = 0 } -- f32, when a vector names no type
local DEFAULT_LENGTH: number = 65535 -- As far as the u16 prefix reaches when a length has no bound
local LONGEST_ENUM_NAME: number = 255 -- What the u8 prefix of an EnumItem's type name can carry
local ID_BYTES_LIMIT: number = 255 -- Messages per direction before ids widen to u16

local FNV_OFFSET: number = 2166136261
local FNV_PRIME_LOW: number = 403 -- The prime 16777619 is 2^24 + 403; the split keeps every product exact
local WORD: number = 2 ^ 32

-- Named types being sized right now, so a reference back into one stops
local visiting: { [TypeDeclaration]: boolean } = {}
local printFields: ({ Field }) -> string

local function fixed(bytes: number): Size
	return { min = bytes, max = bytes, bits = 0, slots = 0 }
end

--[[
    Follows references to the type they name, so a rule about what a value
    is at runtime sees through named types
--]]

local function resolved(node: Type): Type
	while node.kind == "reference" and node.target do
		node = node.target.type
	end

	return node
end

local function isPrimitive(node: Type, name: string): boolean
	local actual: Type = resolved(node)
	return actual.kind == "primitive" and actual.name == name
end

--[[
    The bounds a range declares, without the nil of a missing end
--]]

local function ends(range: Range): { number }
	local list: { number } = {}
	if range.min then
		table.insert(list, range.min)
	end
	if range.max then
		table.insert(list, range.max)
	end
	return list
end

-- A bound printed as a whole number, however large
local function whole(value: number): string
	return string.format("%.0f", value)
end

--[[
    The smallest unsigned prefix that holds a span of lengths
--]]

local function width(span: number): number
	return span <= 255 and 1 or span <= 65535 and 2 or span <= 2 ^ 24 - 1 and 3 or 4
end

--[[
    The prefix bytes and the count bounds of a length: no prefix for an
    exact length, and the u16 default when nothing is declared
--]]

local function lengths(range: Range?): (number, number, number)
	if not range then
		return 2, 0, DEFAULT_LENGTH
	end

	local low: number = range.min or 0
	local high: number = range.max or DEFAULT_LENGTH

	return low == high and 0 or width(high - low), low, high
end

--[[
    The flag bits a discriminant takes, or the bytes it takes instead once
    there are too many variants for a byte
--]]

local function discriminant(count: number): (number, number)
	if count > 256 then
		return 0, 2
	end

	local bits: number = 0
	while 2 ^ bits < count do
		bits += 1
	end

	return bits, 0
end

--[[
    A size laid out as its own block: the flag bytes its bits need, then
    its bytes
--]]

local function block(size: Size): (number, number)
	local flags: number = math.ceil(size.bits / 8)
	return flags + size.min, flags + size.max
end

local function fields(list: { Field }): Size
	local total: Size = fixed(0)
	for _, field: Field in list do
		local size: Size = Analyse.size(field.type)

		total.min += size.min
		total.max += size.max
		total.bits += size.bits
		total.slots += size.slots
	end
	return total
end

--[[
    One of several bodies behind a discriminant, each body a block of its
    own, so a value pays only for the variant it carries
--]]

local function choice(bodies: { Size }): Size
	local bits: number, bytes: number = discriminant(#bodies)
	local size: Size = { min = math.huge, max = 0, bits = bits, slots = 0 }

	for _, body: Size in bodies do
		local low: number, high: number = block(body)

		size.min = math.min(size.min, low)
		size.max = math.max(size.max, high)
		size.slots = math.max(size.slots, body.slots)
	end

	size.min = (#bodies == 0 and 0 or size.min) + bytes
	size.max += bytes

	return size
end

--[[
    A length prefix and then a run of entries, each entry a block
--]]

local function repeated(range: Range?, entry: Size): Size
	local prefix: number, low: number, high: number = lengths(range)
	local entryLow: number, entryHigh: number = block(entry)

	return {
		min = prefix + low * entryLow,
		max = prefix + high * entryHigh,
		bits = 0,
		slots = high * entry.slots,
	}
end

local function roblox(node: Roblox): Size
	local generics: { Type } = node.generics or {}
	local component: Size = generics[1] and Analyse.size(generics[1]) or DEFAULT_COMPONENT

	if node.name == "Vector3" then
		return fixed(3 * component.min)
	elseif node.name == "Vector2" then
		return fixed(2 * component.min)
	elseif node.name == "CFrame" then
		local rotation: Size = generics[2] and Analyse.size(generics[2]) or DEFAULT_COMPONENT
		return fixed(3 * component.min + 3 * rotation.min)
	elseif node.name == "AlignedCFrame" then
		return fixed(1 + 3 * component.min)
	elseif INSTANCES[node.name] then
		return { min = 0, max = 0, bits = 0, slots = 1 }
	elseif node.name == "EnumItem" then
		return { min = 4, max = 3 + LONGEST_ENUM_NAME, bits = 0, slots = 0 }
	end

	return fixed(ROBLOX_BYTES[node.name])
end

--[[
    The bytes a type takes at its least and most, the flag bits it adds to
    the block it sits in, and the most side-array slots it can fill, by the
    wire rules. Total over any tree the parser produces, resolved or not
--]]

function Analyse.size(node: Type | Pack): Size
	if node.kind == "primitive" then
		if node.name == "boolean" then
			return { min = 0, max = 0, bits = 1, slots = 0 }
		elseif node.name == "unknown" then
			return { min = 0, max = 0, bits = 1, slots = 1 }
		elseif node.name == "string" or node.name == "buffer" then
			local prefix: number, low: number, high: number = lengths(node.range)
			return { min = prefix + low, max = prefix + high, bits = 0, slots = 0 }
		end

		return fixed(BYTES[node.name])
	elseif node.kind == "roblox" then
		return roblox(node)
	elseif node.kind == "struct" then
		return fields(node.fields)
	elseif node.kind == "pack" then
		return fields(node.parameters)
	elseif node.kind == "enum" then
		local bodies: { Size } = {}
		for _, variant: Variant in node.variants do
			table.insert(bodies, fields(variant.fields or {}))
		end

		return choice(bodies)
	elseif node.kind == "union" then
		local bodies: { Size } = {}
		for _, member: Type in node.members do
			table.insert(bodies, Analyse.size(member))
		end

		return choice(bodies)
	elseif node.kind == "optional" then
		local inner: Size = Analyse.size(node.inner)

		-- unknown carries its own presence bit, so nil is already a value it can hold
		if isPrimitive(node.inner, "unknown") then
			return inner
		end

		local high: number = select(2, block(inner))
		return { min = 0, max = high, bits = 1, slots = inner.slots }
	elseif node.kind == "array" then
		if not isPrimitive(node.element, "boolean") then
			return repeated(node.range, Analyse.size(node.element))
		end

		-- Booleans pack into a bitset, and an exact count of them into the block's own flags
		local prefix: number, low: number, high: number = lengths(node.range)
		if prefix == 0 then
			return { min = 0, max = 0, bits = low, slots = 0 }
		end

		return { min = prefix + math.ceil(low / 8), max = prefix + math.ceil(high / 8), bits = 0, slots = 0 }
	elseif node.kind == "map" then
		return repeated(
			node.range,
			fields({
				{ name = "", type = node.key, start = 0, finish = 0 },
				{ name = "", type = node.value, start = 0, finish = 0 },
			})
		)
	elseif node.kind == "set" then
		return repeated(node.range, Analyse.size(node.element))
	end

	local target: TypeDeclaration? = node.target
	if not target or visiting[target] then
		return fixed(0)
	end

	visiting[target] = true

	local size: Size = Analyse.size(target.type)
	visiting[target] = nil

	return size
end

--[[
    The runtime classes a union member can be, through references and
    nested unions, which is what the writer tells members apart by
--]]

local function classes(node: Type): { string }
	local actual: Type = resolved(node)

	if actual.kind == "union" then
		local list: { string } = {}
		for _, member: Type in actual.members do
			for _, class: string in classes(member) do
				table.insert(list, class)
			end
		end

		return list
	elseif actual.kind == "primitive" then
		local name: string = actual.name
		local named: boolean = name == "boolean" or name == "string" or name == "buffer" or name == "unknown"

		return { named and name or "number" }
	elseif actual.kind == "roblox" then
		local name: string = actual.name
		local class: string = INSTANCES[name] and "Instance"
			or name == "AlignedCFrame" and "CFrame"
			or name == "Enum" and "EnumItem"
			or name == "DateTimeMillis" and "DateTime"
			or name

		return { class }
	elseif actual.kind == "enum" then
		return { actual.tag and "struct" or "string" }
	elseif actual.kind == "optional" then
		return { "nil" }
	elseif actual.kind == "reference" then
		return {} -- Unresolved, and already reported
	end

	return { actual.kind == "struct" and "struct" or "list" }
end

-- Two unit enums in one union flatten their variants into one discriminant, so they never clash
local function isUnitEnum(node: Type): boolean
	local actual: Type = resolved(node)
	return actual.kind == "enum" and actual.tag == nil
end

local function printRange(range: Range?, open: string, close: string): string
	if not range then
		return ""
	end

	local min: string = range.min and tostring(range.min) or ""
	local max: string = range.max and tostring(range.max) or ""

	return range.min == range.max and `{open}{min}{close}` or `{open}{min}..{max}{close}`
end

--[[
    Prints a type as schema source, with a reference spelled as the full
    path of what it resolved to
--]]

local function printType(node: Type): string
	if node.kind == "primitive" then
		return `{node.name}{printRange(node.range, "(", ")")}`
	elseif node.kind == "roblox" then
		local generics: { string } = {}
		for _, generic: Type in (node.generics or {}) :: { Type } do
			table.insert(generics, printType(generic))
		end

		local item: string = node.item and `.{node.item}` or ""
		local class: string = node.class and `({node.class})` or ""
		local arguments: string = #generics > 0 and `<{table.concat(generics, ", ")}>` or ""

		return `{node.name}{item}{class}{arguments}`
	elseif node.kind == "struct" then
		return `struct \{ {printFields(node.fields)} }`
	elseif node.kind == "enum" then
		local variants: { string } = {}
		for _, variant: Variant in node.variants do
			table.insert(
				variants,
				variant.fields and `{variant.name} \{ {printFields(variant.fields)} }` or variant.name
			)
		end

		local tag: string = node.tag and `"{node.tag}" ` or ""
		return `enum {tag}\{ {table.concat(variants, ", ")} }`
	elseif node.kind == "set" then
		return `set<{printType(node.element)}>{printRange(node.range, "(", ")")}`
	elseif node.kind == "map" then
		return `\{ [{printType(node.key)}]: {printType(node.value)} }{printRange(node.range, "(", ")")}`
	elseif node.kind == "array" then
		return `{printType(node.element)}{node.range and printRange(node.range, "[", "]") or "[]"}`
	elseif node.kind == "optional" then
		return `{printType(node.inner)}?`
	elseif node.kind == "union" then
		local members: { string } = {}
		for _, member: Type in node.members do
			table.insert(members, printType(member))
		end

		return table.concat(members, " | ")
	end

	return node.target and node.target.path or node.name
end

function printFields(list: { Field }): string
	local parts: { string } = {}
	for _, field: Field in list do
		table.insert(parts, `{field.name}: {printType(field.type)}`)
	end

	return table.concat(parts, ", ")
end

--[[
    Prints a record value: a parameter pack, a type, or a plain value
--]]

local function printValue(value: any): string
	if typeof(value) ~= "table" then
		return tostring(value)
	end

	return value.kind == "pack" and `({printFields(value.parameters)})` or printType(value)
end

local function bytes(low: number, high: number): string
	return low == high and `{whole(low)} bytes` or `{whole(low)}..{whole(high)} bytes`
end

local function blockBytes(node: (Type | Pack)?): string
	local low: number, high: number = block(node and Analyse.size(node) or fixed(0))
	return bytes(low, high)
end

--[[
    What resolution and analysis found out about a declaration, as a
    trailing comment; nothing before resolution, so a parsed tree prints
    back as written
--]]

local function annotate(node: Declaration): string
	local parts: { string } = {}

	if node.kind == "type" and node.references then
		local size: Size = Analyse.size(node.type)
		local plural: string = node.references == 1 and "" or "s"

		table.insert(parts, bytes(size.min, size.max))
		if size.bits > 0 then
			table.insert(parts, `{size.bits} flag bit{size.bits == 1 and "" or "s"}`)
		end

		table.insert(parts, `{node.references} reference{plural}`)
	elseif node.kind == "event" and (node.toServer or node.toClient) then
		if node.toServer then
			table.insert(parts, `to server {node.toServer}`)
		end

		if node.toClient then
			table.insert(parts, `to client {node.toClient}`)
		end

		table.insert(parts, `payload {blockBytes(node.data)}`)
	elseif node.kind == "function" and node.toServer then
		table.insert(parts, `to server {node.toServer}`)
		table.insert(parts, `to client {node.toClient}`)
		table.insert(parts, `data {blockBytes(node.data)}`)
		table.insert(parts, `return {blockBytes(node["return"])}`)
	end

	return #parts == 0 and "" or ` -- {table.concat(parts, ", ")}`
end

--[[
    Prints a declaration as schema source, one line each, with record keys
    in shape order, struct and enum declarations in their type form, and a
    namespace's declarations indented under it
--]]

local function printDeclaration(node: Declaration, indent: string): string
	if node.kind == "type" then
		return `{indent}{node.export and "export " or ""}type {node.name} = {printType(node.type)}{annotate(node)}`
	elseif node.kind == "namespace" then
		local inner: { string } = {}
		for _, declaration: Declaration in node.declarations do
			table.insert(inner, printDeclaration(declaration, `{indent}\t`))
		end

		return #inner == 0 and `{indent}namespace {node.name} \{}`
			or `{indent}namespace {node.name} \{\n{table.concat(inner, "\n")}\n{indent}}`
	end

	local entries: { string } = {}
	for _, spec: Spec in node.kind == "event" and Parser.EVENT or Parser.FUNCTION do
		local value: any = (node :: any)[spec.key]

		if value ~= nil then
			table.insert(entries, `{spec.key}: {printValue(value)}`)
		end
	end

	local record: string = #entries == 0 and "{}" or `\{ {table.concat(entries, ", ")} }`
	return `{indent}{node.kind} {node.name} {record}{annotate(node)}`
end

--[[
    Prints a file in its canonical form: the options in their fixed order,
    then the declarations, one per line and each annotated with what
    resolution and analysis found. This text is what the schema hash covers
--]]

function Analyse.print(file: File): string
	local lines: { string } = {}

	for _, spec: Spec in Parser.OPTIONS do
		local value: any = (file.options :: any)[spec.key]

		if value ~= nil then
			table.insert(lines, `option {spec.key} = {spec.kind == "string" and `"{value}"` or tostring(value)}`)
		end
	end

	for _, declaration: Declaration in file.declarations do
		table.insert(lines, printDeclaration(declaration, ""))
	end

	return table.concat(lines, "\n")
end

--[[
    FNV-1a over the bytes of a text, as a 32-bit number
--]]

function Analyse.hash(text: string): number
	local hash: number = FNV_OFFSET
	for index: number = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = (bit32.lshift(hash, 24) + hash * FNV_PRIME_LOW) % WORD
	end
	return hash
end

--[[
    Analyses a resolved file in place: every type checked, every message
    given its ids, every unreliable event held to the budget. Returns the
    schema hash
--]]

function Analyse.file(file: File, diagnostics: Diagnostics): number
	local self = setmetatable({
		_diagnostics = diagnostics,
		_toServer = 0, -- The last id given in each direction
		_toClient = 0,
		_unreliable = {} :: { Event }, -- Checked against the budget once the id widths are known
	}, Analyse)

	self:declarations(file.declarations)
	self:budget(file.options.unreliableBudget :: number)

	return Analyse.hash(Analyse.print(file))
end

--[[
    Walks the declarations in order, checking each type and giving each
    message the next id in every direction it travels
--]]

function Analyse:declarations(declarations: { Declaration })
	for _, declaration: Declaration in declarations do
		if declaration.kind == "type" then
			self:type(declaration.type)
		elseif declaration.kind == "namespace" then
			self:declarations(declaration.declarations)
		else
			if declaration.data then
				self:type(declaration.data)
			end

			if declaration.kind == "function" then
				if declaration["return"] then
					self:type(declaration["return"])
				end

				declaration.toServer = self:next("_toServer")
				declaration.toClient = self:next("_toClient")
			else
				if declaration.from == "Client" or declaration.from == "Both" then
					declaration.toServer = self:next("_toServer")
				end

				if declaration.from == "Server" or declaration.from == "Both" then
					declaration.toClient = self:next("_toClient")
				end

				if declaration.type == "Unreliable" then
					table.insert(self._unreliable, declaration)
				end
			end
		end
	end
end

function Analyse:next(direction: string): number
	self[direction] += 1
	return self[direction]
end

--[[
    Refuses every unreliable event whose largest message, id included,
    would not fit one fire
--]]

function Analyse:budget(budget: number)
	for _, event: Event in self._unreliable do
		local wide: boolean = (event.toServer ~= nil and self._toServer > ID_BYTES_LIMIT)
			or (event.toClient ~= nil and self._toClient > ID_BYTES_LIMIT)
		local idBytes: number = wide and 2 or 1
		local largest: number = idBytes + select(2, block(event.data and Analyse.size(event.data) or fixed(0)))

		if largest > budget then
			local message: string =
				`event {event.path} can reach {largest} bytes, over the unreliable budget of {budget}`
			self._diagnostics:error("V3010", message, event.spans.type)
		end
	end
end

--[[
    Checks one type node and everything inside it
--]]

function Analyse:type(node: Type | Pack)
	if node.kind == "primitive" then
		self:range(node)
	elseif node.kind == "roblox" then
		self:roblox(node)
	elseif node.kind == "array" then
		self:lengths(node.range)
	elseif node.kind == "map" then
		self:key(node.key, "a map key")
		self:lengths(node.range)
	elseif node.kind == "set" then
		self:key(node.element, "a set element")
		self:lengths(node.range)
	elseif node.kind == "union" then
		self:union(node)
	end

	for _, child: Type in Parser.children(node) do
		self:type(child)
	end
end

--[[
    A primitive's range: mandatory and two-ended on a quantised float,
    refused on a boolean or unknown, a length on a string or buffer, and
    whole and within the bounds on an integer
--]]

function Analyse:range(node: Type)
	local name: string = (node :: any).name
	local range: Range? = (node :: any).range

	if name == "q8" or name == "q16" then
		if not (range and range.min and range.max and range.min < range.max) then
			self._diagnostics:error("V3011", `{name} needs a range with both ends, such as {name}(0..1)`, range or node)
		end

		return
	end

	if not range then
		return
	elseif name == "boolean" or name == "unknown" then
		return self._diagnostics:error("V3011", `{name} takes no range`, range)
	elseif name == "string" or name == "buffer" then
		return self:lengths(range)
	elseif range.min and range.max and range.min > range.max then
		return self._diagnostics:error("V3011", "a range's minimum is above its maximum", range)
	end

	local bounds: { number }? = BOUNDS[name]
	if not bounds then
		return -- A float takes any range
	end

	for _, limit: number in ends(range) do
		if limit % 1 ~= 0 then
			return self._diagnostics:error("V3011", `{name}'s range has a fractional end, {limit}`, range)
		elseif limit < bounds[1] or limit > bounds[2] then
			local message: string = `{name}'s range is outside its bounds {whole(bounds[1])}..{whole(bounds[2])}`
			return self._diagnostics:error("V3011", message, range)
		end
	end
end

--[[
    A length range on a string, buffer, array, map or set: whole numbers
    from zero up, in order
--]]

function Analyse:lengths(range: Range?)
	if not range then
		return
	end

	for _, limit: number in ends(range) do
		if limit < 0 or limit % 1 ~= 0 then
			local message: string = `a length must be a whole number of at least 0, got {limit}`
			return self._diagnostics:error("V3011", message, range)
		end
	end

	if range.min and range.max and range.min > range.max then
		self._diagnostics:error("V3011", "a range's minimum is above its maximum", range)
	end
end

--[[
    A Roblox type's arguments: as many numeric primitives as the type
    takes, and a class only on an instance
--]]

function Analyse:roblox(node: Roblox)
	local allowed: number = GENERICS[node.name] or 0
	local generics: { Type }? = node.generics

	if generics and #generics ~= allowed then
		local takes: string = allowed == 0 and "no type arguments"
			or `{COUNTS[allowed]} numeric type argument{allowed == 1 and "" or "s"}`
		self._diagnostics:error("V3007", `{node.name} takes {takes}, got {#generics}`, node)
	elseif generics then
		for _, generic: Type in generics do
			if generic.kind ~= "primitive" or not BYTES[generic.name] then
				local message: string =
					`{node.name}'s type argument must be a numeric primitive, got {printType(generic)}`
				self._diagnostics:error("V3007", message, generic)
			end
		end
	end

	if node.class and not INSTANCES[node.name] then
		self._diagnostics:error("V3007", `{node.name} takes no class`, node)
	end
end

--[[
    A map key or set element must be a value Luau can index a table by
    and the reader can compare for duplicates
--]]

function Analyse:key(node: Type, label: string)
	local actual: Type = resolved(node)
	local allowed: boolean = (actual.kind == "primitive" and actual.name ~= "unknown")
		or actual.kind == "roblox"
		or (actual.kind == "enum" and actual.tag == nil)
		or actual.kind == "reference"

	if not allowed then
		local message: string = `{label} must be a primitive, string, enum or Roblox type, got {printType(node)}`
		self._diagnostics:error("V3008", message, node)
	end
end

--[[
    Two union members the writer could not tell apart by typeof and shape
    are refused, as is a member that can be nil or anything at all
--]]

function Analyse:union(node: Type)
	local seen: { [string]: Type } = {}

	for _, member: Type in (node :: any).members do
		for _, class: string in classes(member) do
			local first: Type? = seen[class]

			if class == "nil" then
				local message: string =
					`union member {printType(member)} is optional; make the whole union optional instead`
				self._diagnostics:error("V3009", message, member)
			elseif class == "unknown" then
				self._diagnostics:error("V3009", "unknown cannot be a union member; it already takes any value", member)
			elseif first and not (isUnitEnum(first) and isUnitEnum(member)) then
				local both: string = CLASSES[class] or `{class} values`
				local message: string =
					`union members {printType(first)} and {printType(member)} are both {both} at runtime`
				self._diagnostics:error("V3009", message, member)
			end

			seen[class] = first or member
		end
	end
end

-- The emitter lays bytes out by the same tables and rules analysis sizes them with
Analyse.BYTES = BYTES
Analyse.BOUNDS = BOUNDS
Analyse.prefix = lengths
Analyse.printType = printType

return Analyse
