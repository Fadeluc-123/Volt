--[[
    Where an AwaitedInstance may travel: whether a type reaches one through
    its fields and named types, and the check that refuses one anywhere but
    the data of a from: Server event that is not ordered, and warns about a
    timeout on an event whose data reaches none
--]]

--!strict
local Awaits = {}

local Diagnostics = require("../Diagnostics")
local Parser = require("../Parser")
local Print = require("./Print")
local Roblox = require("../Config/Roblox")
local Schema = require("../Config/Types/Schema")

type Declaration = Schema.Declaration
type Diagnostics = Diagnostics.Diagnostics
type Pack = Schema.Pack
type Roblox = Schema.Roblox
type Span = Diagnostics.Span
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration

-- Where an AwaitedInstance may travel, as a refusal names it
local SERVER: string = "a from: Server event's data"
local UNORDERED: string = "a Reliable or Unreliable event's data" -- A replay would deliver past the sequence check

local TIMEOUT: string = "timeout on an event whose data reaches no AwaitedInstance has no effect; nothing waits"

--[[
    Adds every AwaitedInstance a type reaches to the list, following each
    named type once, so a type named twice or one that contains itself
    adds nothing more
--]]

local function collect(node: Type | Pack, list: { Roblox }, walked: { [TypeDeclaration]: boolean })
	if node.kind == "reference" then
		local target: TypeDeclaration? = node.target

		if target and not walked[target] then
			walked[target] = true
			collect(target.type, list, walked)
		end

		return
	elseif node.kind == "roblox" and Roblox[node.name].awaited then
		table.insert(list, node)
	end

	for _, child: Type in Parser.children(node) do
		collect(child, list, walked)
	end
end

-- Every AwaitedInstance a type reaches through its named types, in the order the walk finds them
local function found(node: (Type | Pack)?): { Roblox }
	local list: { Roblox } = {}

	if node then
		collect(node, list, {})
	end

	return list
end

-- Whether a message's data reaches an AwaitedInstance, which ends its client reader in the runtime's await
function Awaits.reaches(node: (Type | Pack)?): boolean
	return #found(node) > 0
end

-- Refuses every AwaitedInstance a type reaches, at the AwaitedInstance, naming where it may travel and what reaches it
local function refuse(diagnostics: Diagnostics, node: (Type | Pack)?, allowed: string, reason: string)
	for _, awaited: Roblox in found(node) do
		diagnostics:error("V3022", `{Print.type(awaited)} travels only in {allowed}; {reason}`, awaited)
	end
end

--[[
    Holds every message and exported type to where an AwaitedInstance may
    travel: only the data of a from: Server event, since the server never
    reads an id, an exported type's read cannot wait, and an ordered
    event's replay would skip its sequence check; then warns about a
    timeout on an event whose data reaches no AwaitedInstance
--]]

function Awaits.check(diagnostics: Diagnostics, declarations: { Declaration })
	for _, declaration: Declaration in declarations do
		if declaration.kind == "namespace" then
			Awaits.check(diagnostics, declaration.declarations)
		elseif declaration.kind == "type" and declaration.export then
			refuse(diagnostics, declaration.type, SERVER, `{declaration.path} is exported`)
		elseif declaration.kind == "function" then
			refuse(diagnostics, declaration.data, SERVER, `{declaration.path} is a function`)
			refuse(diagnostics, declaration["return"], SERVER, `{declaration.path} is a function`)
		elseif declaration.kind == "event" then
			local timeout: Span? = declaration.spans.timeout

			if declaration.from ~= "Server" then
				refuse(diagnostics, declaration.data, SERVER, `{declaration.path} is from: {declaration.from}`)
			elseif declaration.type == "OrderedUnreliable" then
				refuse(diagnostics, declaration.data, UNORDERED, `{declaration.path} is OrderedUnreliable`)
			end

			if timeout and not Awaits.reaches(declaration.data) then
				diagnostics:warn("V3006", TIMEOUT, timeout)
			end
		end
	end
end

return Awaits
