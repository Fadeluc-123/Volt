--[[
    Walks a type once and writes its serialiser and its deserialiser into
    a pair of blocks as it goes, so both sides come from one traversal
    and cannot disagree. This file holds the emitter's state, the walk
    of a block and the dispatch on a type's kind, the function pair a
    shared named type becomes and the constants a module carries; each
    kind of type is walked by the methods of one sibling file
--]]

--!strict
local Emit = {} :: any
Emit.__index = Emit

-- An init file stands for its folder, so its siblings are reached through the folder's name
local Blocks = require("./Blocks")
local Collections = require("./Emit/Collections")
local Composites = require("./Emit/Composites")
local Contract = require("./Config/Contract")
local Expressions = require("./Emit/Expressions")
local Primitives = require("./Config/Primitives")
local Roblox = require("./Emit/Roblox")
local Scalars = require("./Emit/Scalars")
local Schema = require("./Config/Types/Schema")
local Sizes = require("./Analyse/Sizes")

type Block = Blocks.Block
type Field = Schema.Field
type Options = Schema.Options
type Pack = Schema.Pack
type Parameter = Contract.Parameter
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration

function Emit.new(options: Options)
	return setmetatable({
		_validate = options.writeValidation ~= false, -- Whether writers check their values
		_known = false, -- Whether the value being walked already had its Luau type established
		_constants = {} :: { [string]: string }, -- Constant names by what they hold, so one table serves every use
		_names = {} :: { [string]: boolean }, -- Every constant name taken
		_shared = {} :: { [TypeDeclaration]: boolean }, -- The named types whose pair is emitted
		helpers = {} :: { [string]: boolean }, -- The helpers the walked types needed
		constants = {} :: { string }, -- The module-level tables the walked types need, in first-use order
		functions = {} :: { string }, -- The function pairs of shared named types, each after the pairs it calls
	}, Emit)
end

--[[
    A parameter list for a generated function, with each parameter the
    body never reaches for named _, so a linter has nothing to say
--]]

function Emit.parameters(body: string, list: { Parameter }): string
	local parts: { string } = {}
	for _, parameter: Parameter in list do
		local used: boolean = body:find(`%f[%w_]{parameter.name}%f[^%w_]`) ~= nil
		table.insert(parts, used and `{parameter.name}: {parameter.type}` or "_")
	end
	return table.concat(parts, ", ")
end

--[[
    Emits one block's worth of a type into both sides: the flag bytes the
    block needs are reserved first, then the type is walked. A pack walks
    each parameter under its own name; anything else is one value.
    Returns the names the write side takes its values by and the
    expressions the read side yields them as
--]]

function Emit:block(node: Type | Pack, write: Block, read: Block): ({ string }, { string })
	local bits: number = Sizes.size(node).bits
	local names: { string } = {}
	local values: { string } = {}

	write:flags(bits)
	read:flags(bits)

	if node.kind ~= "pack" then
		local name: string = write:name("value")
		return { name }, { self:type(node, write, read, name, "value", write.path) }
	end

	-- Every parameter takes its name before any walk claims a helper local
	for _, parameter: Field in node.parameters do
		table.insert(names, write:name(parameter.name))
	end

	for index: number, parameter: Field in node.parameters do
		local path: string = `{write.path}.{parameter.name}`
		table.insert(values, self:type(parameter.type, write, read, names[index], parameter.name, path))
	end

	return names, values
end

--[[
    The function pair a shared named type is called through, emitted once
    and in dependency order, since walking a type emits the pairs of the
    shared types it references first. Returns the name the pair carries
--]]

function Emit:shared(target: TypeDeclaration): string
	local path: string = target.path :: string
	local name: string = path:gsub("%.", "_")

	if self._shared[target] then
		return name
	end

	self._shared[target] = true

	local known: boolean = self._known
	local write: Block = Blocks.new("write", path)
	local read: Block = Blocks.new("read", path)

	self._known = false

	local names: { string }, values: { string } = self:block(target.type, write, read)
	local writeBody: string = write:done()
	local readBody: string = read:done(`return cursor, sideCursor, {values[1]}`)
	local taken: { Parameter } = table.clone(Contract.write)

	table.insert(taken, { name = names[1], type = "any" })
	self._known = known

	table.insert(self.functions, `local function write{name}({Emit.parameters(writeBody, taken)})\n{writeBody}end\n`)
	table.insert(
		self.functions,
		`local function read{name}({Emit.parameters(readBody, Contract.read)})\n{readBody}end\n`
	)

	return name
end

--[[
    A reference to a shared named type: the write side hands the pair
    what it writes through, then its value; the read side takes the value
    and the advanced cursors back, both after the block's own bytes
--]]

function Emit:call(target: TypeDeclaration, write: Block, read: Block, value: string, hint: string): string
	local name: string = self:shared(target)
	local result: string = read:name(hint)
	local passed: { string } = {}

	for _, parameter: Parameter in Contract.write do
		table.insert(passed, (write :: any)[parameter.name])
	end

	table.insert(passed, value)
	write:tail(`write{name}({table.concat(passed, ", ")})`)
	
	read:line(`local {result}`)
	read:tail(`cursor, sideCursor, {result} = read{name}(packet, cursor, side, sideCursor, length)`)

	return result
end

--[[
    Walks one type on both sides. value is the write side's expression
    for it, hint names the read side's local, path names it in a failure
--]]

function Emit:type(node: Type, write: Block, read: Block, value: string, hint: string, path: string): string
	if node.kind == "reference" then
		local target: TypeDeclaration = node.target :: TypeDeclaration
		if Sizes.shared(target) then
			return self:call(target, write, read, value, hint)
		end

		return self:type(target.type, write, read, value, hint, path)
	elseif node.kind == "primitive" then
		if node.name == "boolean" then
			return self:boolean(write, read, value, path)
		elseif node.name == "unknown" then
			return self:unknown(write, read, value, hint, path)
		elseif node.name == "string" or node.name == "buffer" then
			return self:bytes(node, write, read, value, hint, path)
		elseif Primitives[node.name].levels then
			return self:quantised(node, write, read, value, hint, path)
		end

		return self:number(node, write, read, value, hint, path)
	elseif node.kind == "roblox" then
		return self:roblox(node, write, read, value, hint, path)
	elseif node.kind == "struct" then
		return self:struct(node, write, read, value, hint, path)
	elseif node.kind == "optional" then
		return self:optional(node, write, read, value, hint, path)
	elseif node.kind == "enum" then
		return self:enum(node, write, read, value, hint, path)
	elseif node.kind == "union" then
		return self:union(node, write, read, value, hint, path)
	elseif node.kind == "array" then
		return self:array(node, write, read, value, hint, path)
	end

	return self:map(node, write, read, value, hint, path)
end

--[[
    Refuses a value of the wrong Luau type on the write side, unless
    validation is off or whatever walked the value here established it
--]]

function Emit:shape(write: Block, value: string, luauType: string, path: string)
	if self._validate and not self._known then
		Expressions.refuse(write, `typeof({value}) ~= "{luauType}"`, `{path}: expected {luauType}`)
	end
end

-- Sets whether writers check their values and returns what it was, so a walk can be checked whatever the option says
function Emit:validating(on: boolean): boolean
	local was: boolean = self._validate
	self._validate = on
	return was
end

--[[
    A module-level table a type needs, emitted once per distinct content
    and named after where it was first needed, in SCREAMING_SNAKE
--]]

function Emit:constant(key: string, hint: string, render: (string) -> string): string
	local existing: string? = self._constants[key]
	if existing then
		return existing
	end

	local snake: string = hint:gsub("%W+", "_"):gsub("_$", "")
	local base: string = string.upper(snake)
	local name: string = base
	local suffix: number = 1

	while self._names[name] do
		suffix += 1
		name = `{base}_{suffix}`
	end

	self._names[name] = true
	self._constants[key] = name

	table.insert(self.constants, render(name))

	return name
end

-- Each kind of type is walked by the methods of one sibling file, and a name defined twice is a bug
for _, part in { Scalars, Roblox, Composites, Collections } do
	for name: string, method in part do
		assert(Emit[name] == nil, `Emit.{name} is defined twice`)
		Emit[name] = method
	end
end

return Emit
