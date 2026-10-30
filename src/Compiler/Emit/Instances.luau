--[[
    The instance walks, merged onto the emitter: an instance or a streamed
    one as a side-array slot, and an awaited one as the id its scope gives
    it, which the client looks up and the runtime waits on until the
    instance has arrived
--]]

--!strict
local Instances = {}

local Blocks = require("../Blocks")
local Expressions = require("./Expressions")
local Print = require("../Analyse/Print")
local Roblox = require("../Config/Roblox")
local Schema = require("../Config/Types/Schema")
local Types = require("../Config/Types/Emit")

type Block = Blocks.Block
type Emit = Types.Emit
type Roblox = Schema.Roblox

local refuse = Expressions.refuse
local writeNumber = Expressions.writeNumber
local readNumber = Expressions.readNumber

--[[
    Refuses on the write side what no instance of the type can be: nil on
    every build, since an empty slot fails the receiver's decode and nil
    has no id, and the wrong class when validating. A value the walk
    already established as an instance is not checked for one again
--]]

local function guard(self: Emit, node: Roblox, write: Block, value: string, expected: string)
	local class: string? = node.class
	local terms: { string } = {}

	if not self._known then
		table.insert(terms, self._validate and `typeof({value}) ~= "Instance"` or `{value} == nil`)
	end

	-- Out of a shared pair's any the checker has nothing to call IsA on, so the value is cast to what it was checked as
	if self._validate and class then
		table.insert(terms, `not ({value} :: Instance):IsA("{class}")`)
	end

	if #terms > 0 then
		refuse(write, table.concat(terms, " or "), expected)
	end
end

--[[
    An instance: no bytes, one side-array slot. The reader refuses
    anything but an instance of the class, or for a streamed instance
    anything present that is not one
--]]

function Instances.instance(
	self: Emit,
	node: Roblox,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local class: string? = node.class
	local streamed: boolean = node.name == "StreamedInstance"
	local expected: string = `{path}: expected {Print.type(node)}`
	local result: string = read:name(hint)

	guard(self, node, write, value, expected)

	write:line(`{write.slot}({value})`)
	read:line(`local {result}: {class or "Instance"}? = side[sideCursor]`)
	read:line("sideCursor += 1")

	if streamed and class then
		refuse(read, `{result} ~= nil and not {result}:IsA("{class}")`, expected)
	elseif not streamed then
		local isA: string = class and ` or not {result}:IsA("{class}")` or ""
		refuse(read, `typeof({result}) ~= "Instance"{isA}`, expected)
	end

	return result
end

--[[
    An awaited instance: the id its scope gives it, an unsigned integer of
    the row's bytes, and no slot. The reader looks the id up; one whose
    instance has not arrived reads as nil, which the runtime's await waits
    on, so only an instance that has arrived is held to the class, and the
    value is handed on as the class, since the runtime delivers it only then
--]]

function Instances.awaited(
	self: Emit,
	node: Roblox,
	write: Block,
	read: Block,
	value: string,
	hint: string,
	path: string
): string
	local class: string = node.class or "Instance"
	local expected: string = `{path}: expected {Print.type(node)}`
	local bytes: number = Roblox[node.name].bytes :: number
	local width: string = `u{bytes * 8}`
	local index: number = write:reserve(bytes)
	local at: number = read:reserve(bytes)
	local result: string = read:name(hint)

	-- The lookup gives an Instance, which a narrower class is cast down from
	local cast: string = node.class and ` :: {class}?` or ""

	guard(self, node, write, value, expected)

	-- Out of a shared pair's any the checker cannot pick the call's result, so the value is cast as the guard casts it
	writeNumber(write, width, index, `instanceId({value} :: Instance)`)
	read:line(`local {result}: {class}? = instanceById({readNumber(read, width, at)}){cast}`)

	if node.class then
		refuse(read, `{result} ~= nil and not {result}:IsA("{class}")`, expected)
	end

	return `{result} :: {class}`
end

return Instances
