--[[
    Holds the replication attributes to their rules: a @delta event is the
    server's, reliable and carries one struct a client never reads a nil
    from or waits for, a @dictionary type is a short string, and only what
    the server writes on its default reliable stream may reach one
--]]

--!strict
local Replication = {}

local Diagnostics = require("../Diagnostics")
local Parser = require("../Parser")
local Print = require("./Print")
local Schema = require("../Config/Types/Schema")
local Sizes = require("./Sizes")
local Wire = require("../Config/Wire")

type Declaration = Schema.Declaration
type Diagnostics = Diagnostics.Diagnostics
type Event = Schema.Event
type Field = Schema.Field
type Pack = Schema.Pack
type Type = Schema.Type
type TypeDeclaration = Schema.TypeDeclaration

local ENTRY_BYTES: number = Wire.entryBytes
local MASK_BITS: number = 32 -- A mask is one bit32 word, a bit per field

local STREAM: string = "the server's default reliable stream" -- The one stream the dictionary is sent ahead of

--[[
    Adds every node of a type that picks accepts to the list, following
    each named type once, so a type named twice or one that contains
    itself adds nothing more
--]]

local function collect(
	node: Type | Pack,
	picks: (Type | Pack) -> boolean,
	list: { Type },
	walked: { [TypeDeclaration]: boolean }
)
	if picks(node) then
		table.insert(list, node :: Type)
		return
	elseif node.kind == "reference" then
		local target: TypeDeclaration? = node.target

		if target and not walked[target] then
			walked[target] = true
			collect(target.type, picks, list, walked)
		end

		return
	end

	for _, child: Type in Parser.children(node) do
		collect(child, picks, list, walked)
	end
end

-- Every node a type reaches that picks accepts, in the order the walk finds them
local function found(node: (Type | Pack)?, picks: (Type | Pack) -> boolean): { Type }
	local list: { Type } = {}

	if node then
		collect(node, picks, list, {})
	end

	return list
end

-- A reference to a @dictionary type, whose id only the server's default reliable stream may carry
local function dictionary(node: Type | Pack): boolean
	local target: TypeDeclaration? = node.kind == "reference" and node.target or nil
	return target ~= nil and target.attributes ~= nil and target.attributes.dictionary == true
end

-- A value a client can read as nil where the server sent one, which a field the mask leaves out would keep
local function nilable(node: Type | Pack): boolean
	return (node.kind == "roblox" and node.name == "StreamedInstance")
		or (node.kind == "primitive" and node.name == "unknown")
end

-- An instance a client can wait for: its reader merges before the message waits, and again when it is read again
local function awaited(node: Type | Pack): boolean
	return node.kind == "roblox" and node.name == "AwaitedInstance"
end

--[[
    A @dictionary type is a string, byte or UTF-8, through any named type,
    whose longest value fits one dictionary entry
--]]

local function short(diagnostics: Diagnostics, declaration: TypeDeclaration)
	local actual: Type = Sizes.resolved(declaration.type)
	local most: number? = actual.kind == "primitive" and actual.name == "string" and actual.range and actual.range.max
		or nil

	if most == nil or most > ENTRY_BYTES then
		local written: string = Print.type(declaration.type)
		local message: string =
			`@dictionary type {declaration.path} must be a string of at most {ENTRY_BYTES} bytes, got {written}`
		diagnostics:error("V3016", message, declaration.type)
	end
end

--[[
    A @delta event is the server's and reliable, each refused at its key,
    and carries one struct of 1 to 32 fields reaching nothing a client can
    read as nil, since a field the mask leaves out would keep that nil,
    and nothing it can wait for, since a waiting message would merge twice
--]]

local function delta(diagnostics: Diagnostics, event: Event)
	local named: string = `@delta event {event.path}`
	local data: (Type | Pack)? = event.data
	local fields: { Field }? = nil
	local carried: string = "nothing"

	-- A key the record left out is already reported missing, so the refusal falls back to the event's name
	if event.from ~= "Server" then
		diagnostics:error("V3015", `{named} must be from: Server; it is from: {event.from}`, event.spans.from or event)
	end

	if event.type ~= "Reliable" then
		diagnostics:error("V3015", `{named} must be Reliable; it is {event.type}`, event.spans.type or event)
	end

	if data and data.kind == "pack" then
		carried = "a parameter pack"
	elseif data then
		local actual: Type = Sizes.resolved(data)

		fields = actual.kind == "struct" and actual.fields or nil
		carried = Print.type(data)
	end

	if not fields then
		return diagnostics:error("V3015", `{named} must carry one struct; it carries {carried}`, data or event)
	end

	if #fields == 0 or #fields > MASK_BITS then
		local message: string = `{named}'s struct must have 1 to {MASK_BITS} fields; it has {#fields}`
		diagnostics:error("V3015", message, data or event)
	end

	for _, node: Type in found(data, nilable) do
		diagnostics:error("V3015", `{named} cannot carry {Print.type(node)}, which a client can read as nil`, node)
	end

	for _, node: Type in found(data, awaited) do
		diagnostics:error("V3015", `{named} cannot carry {Print.type(node)}, which a client can wait for`, node)
	end
end

-- Refuses every @dictionary type a type reaches, at the reference, saying why it may not travel there
local function refuse(diagnostics: Diagnostics, node: (Type | Pack)?, reason: string)
	for _, reference: Type in found(node, dictionary) do
		local message: string = `@dictionary type {Print.type(reference)} travels only on {STREAM}; {reason}`
		diagnostics:error("V3017", message, reference)
	end
end

--[[
    Checks every declaration's replication attributes, namespaces walked,
    and holds every @dictionary type to the server's default reliable
    stream: never in a message the client writes, an unreliable event, an
    event on a channel or an exported type
--]]

function Replication.check(diagnostics: Diagnostics, declarations: { Declaration })
	for _, declaration: Declaration in declarations do
		if declaration.kind == "namespace" then
			Replication.check(diagnostics, declaration.declarations)
		elseif declaration.kind == "type" then
			if declaration.attributes and declaration.attributes.dictionary then
				short(diagnostics, declaration)
			end

			if declaration.export then
				refuse(diagnostics, declaration.type, `{declaration.path} is exported`)
			end
		elseif declaration.kind == "function" then
			refuse(diagnostics, declaration.data, `{declaration.path} is a function`)

			-- The client writes a from: Server function's reply
			if declaration.from == "Server" then
				refuse(diagnostics, declaration["return"], `{declaration.path}'s return is the client's reply`)
			end
		elseif declaration.kind == "event" then
			local path: string = declaration.path :: string
			local reason: string? = declaration.from ~= "Server" and `{path} is from: {declaration.from}`
				or declaration.type ~= "Reliable" and `{path} is {declaration.type}`
				or declaration.channel and `{path} rides channel {declaration.channel}`
				or nil

			if declaration.attributes and declaration.attributes.delta then
				delta(diagnostics, declaration)
			end

			if reason then
				refuse(diagnostics, declaration.data, reason)
			end
		end
	end
end

return Replication
