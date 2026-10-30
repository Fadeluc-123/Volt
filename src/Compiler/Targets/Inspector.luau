--[[
    The packet inspector PacketProfiler calls: both sides' readers, walked
    again unlabelled by an emitter that reads an awaited instance and a
    dictionary string as the ids they travel as, each tail noting its
    message in the runtime's place, and the function that reads a packet
    of the scope's remotes into the messages it holds, never raising
--]]

--!strict
local Inspector = {}

local Blocks = require("../Blocks")
local Contract = require("../Config/Contract")
local Diagnostics = require("../Diagnostics")
local Emit = require("../Emit")
local Expressions = require("../Emit/Expressions")
local Output = require("../Config/Output")
local Pieces = require("./Pieces")
local Roblox = require("../Config/Roblox")
local Schema = require("../Config/Types/Schema")
local Sizes = require("../Analyse/Sizes")
local TargetsTypes = require("../Config/Types/Targets")
local Types = require("./Types")
local Wire = require("../Config/Wire")

type Block = Blocks.Block
type Diagnostics = Diagnostics.Diagnostics
type Emit = TargetsTypes.Emit
type Extra = TargetsTypes.Extra
type Options = Schema.Options
type Roblox = Schema.Roblox
type Declared = Schema.TypeDeclaration
type Targets = TargetsTypes.Targets

local VERSION: string = Contract.version
local FOLDER: string = Contract.folder
local STATUSES: number = Contract.statuses
local FILE_LOCALS: number = Output.fileLocals
local HANDSHAKE_BYTES: number = Wire.handshakeBytes
local CHANNEL_BYTES: number = Wire.channelBytes
local STAMP_BYTES: number = Wire.stampBytes
local DICTIONARY_BYTES: number = Wire.dictionaryBytes
local DICTIONARY_ID: string = `u{DICTIONARY_BYTES * 8}` -- The primitive a dictionary string's id is read as
local BOT: string = "type Bot = { Name: string }" -- A bot's shape, since no runtime is required for its type

-- The prefix and the most of a refusal's reason, by the length rule the runtime reads it with
local REASON_PREFIX: number, _, REASON_MAX: number =
	Sizes.lengths({ min = 0, max = Wire.replyMessage, start = 0, finish = 0 })

-- What a reader's tail calls in a packet the inspector reads: each notes the message, and hands the cursors back
local RECORDER: string = table.concat({
	"local runtime = {",
	"\tcalls = {} :: { { Name: string, Arguments: { any } } },",
	`\treading = "",`,
	"",
	"\tnote = function (self: any, name: string, cursor: number, sideCursor: number, ...: any): (number, number)",
	"\t\ttable.insert(self.calls, { Name = name, Arguments = { ... } })",
	"",
	"\t\treturn cursor, sideCursor",
	"\tend,",
	"",
	"\tdeliver = function (self: any, _: number, _: any, cursor: number, sideCursor: number, ...: any): (number, number)",
	"\t\treturn self:note(self.reading, cursor, sideCursor, ...)",
	"\tend,",
	"",
	"\tawait = function (self: any, _: number, _: buffer, _: number, cursor: number, _: { any }, _: number, sideCursor: number, ...: any): (number, number)",
	"\t\treturn self:note(self.reading, cursor, sideCursor, ...)",
	"\tend,",
	"",
	"\tordered = function (self: any, _: number, sequence: number, _: any, cursor: number, sideCursor: number, ...: any): (number, number)",
	"\t\treturn self:note(self.reading, cursor, sideCursor, sequence, ...)",
	"\tend,",
	"",
	"\tmerge = function (_: any, _: number, mask: number, partial: { [string]: any }): (number, { [string]: any })",
	"\t\treturn mask, partial",
	"\tend,",
	"",
	"\tcall = function (self: any, _: number, _: any, _: number, cursor: number, sideCursor: number, ...: any): (number, number)",
	"\t\treturn self:note(`{self.reading} (call)`, cursor, sideCursor, ...)",
	"\tend,",
	"",
	"\treply = function (self: any, _: number, _: any, _: number, cursor: number, sideCursor: number, ...: any): (number, number)",
	"\t\treturn self:note(`{self.reading} (reply)`, cursor, sideCursor, true, ...)",
	"\tend,",
	"",
	"\trefused = function (self: any, _: number, _: any, _: number, status: number, packet: buffer, cursor: number, sideCursor: number, length: number): (number, number)",
	`\t\tif status > {STATUSES} then`,
	"\t\t\terror(`{self.reading}: unknown status {status}`)",
	"\t\tend",
	"",
	`\t\tif cursor + {REASON_PREFIX} > length then`,
	"\t\t\terror(`{self.reading}: truncated`)",
	"\t\tend",
	"",
	`\t\tlocal count: number = buffer.readu{REASON_PREFIX * 8}(packet, cursor)`,
	`\t\tcursor += {REASON_PREFIX}`,
	"",
	`\t\tif count > {REASON_MAX} or cursor + count > length then`,
	"\t\t\terror(`{self.reading}: truncated`)",
	"\t\tend",
	"",
	"\t\treturn self:note(`{self.reading} (reply)`, cursor + count, sideCursor, false, buffer.readstring(packet, cursor, count))",
	"\tend,",
	"}",
	"",
}, "\n")

-- A client's reader of the dictionary message, id 0, checked as the runtime checks it but for what only it holds
local DICTIONARY: string = table.concat({
	"[0] = {",
	`\tname = "Volt dictionary",`,
	"\tread = function (_: (Player | Bot)?, packet: buffer, cursor: number, _: { any }, sideCursor: number, length: number): (number, number)",
	`\t\tif cursor + {2 * DICTIONARY_BYTES} > length then`,
	`\t\t\terror("Volt dictionary: truncated")`,
	"\t\tend",
	"",
	`\t\tlocal entries: \{ any } = \{ buffer.read{DICTIONARY_ID}(packet, cursor) }`,
	`\t\tlocal count: number = buffer.read{DICTIONARY_ID}(packet, cursor + {DICTIONARY_BYTES})`,
	`\t\tcursor += {2 * DICTIONARY_BYTES}`,
	"",
	"\t\tif count == 0 then",
	`\t\t\terror("Volt dictionary: no entries")`,
	"\t\tend",
	"",
	"\t\tfor index = 1, count do",
	"\t\t\tlocal bytes: number = cursor < length and buffer.readu8(packet, cursor) or length",
	"\t\t\tcursor += 1",
	"",
	"\t\t\tif cursor + bytes > length then",
	`\t\t\t\terror("Volt dictionary: truncated")`,
	"\t\t\tend",
	"",
	"\t\t\tentries[index + 1] = buffer.readstring(packet, cursor, bytes)",
	"\t\t\tcursor += bytes",
	"\t\tend",
	"",
	`\t\treturn runtime:note("Volt dictionary", cursor, sideCursor, table.unpack(entries))`,
	"\tend,",
	"},",
}, "\n")

-- What the readers of each direction are held in, by id, beside the name each message is noted by
local MESSAGES: string =
	"{ [string]: { [number]: { name: string, read: (player: (Player | Bot)?, packet: buffer, cursor: number, side: { any }, sideCursor: number, length: number) -> (number, number) } } }"

-- The walks an inspector's emitter takes in place of the modules' own, for the two reads only a runtime resolves
local Reading = {}
Reading.__index = Reading

setmetatable(Reading, { __index = Emit })

-- An awaited instance, read as the id it travels as, since only a client's runtime holds the instance an id names
function Reading.awaited(_: Emit, node: Roblox, write: Block, read: Block, _: string, hint: string, _: string): string
	local bytes: number = Roblox[node.name].bytes :: number
	local width: string = `u{bytes * 8}`
	local id: string = read:name(hint)

	-- The write side takes the bytes too, though no writer of an inspector's walk is kept
	write:reserve(bytes)
	read:line(`local {id}: number = {Expressions.readNumber(read, width, read:reserve(bytes))}`)

	return `{id} :: any`
end

-- A @dictionary string, read as the id it travels as, since only a client's runtime holds the entry an id names
function Reading.dictionary(_: Emit, _: Declared, write: Block, read: Block, _: string, hint: string, _: string): string
	local id: string = read:name(hint)

	write:reserve(DICTIONARY_BYTES)
	read:line(`local {id}: number = {Expressions.readNumber(read, DICTIONARY_ID, read:reserve(DICTIONARY_BYTES))}`)

	return `{id} :: any`
end

--[[
    One direction's messages by id, each named as its schema row names it
    beside its reader, and a client's dictionary message at 0 in a schema
    with a dictionary. Returns the table's entry and its readers' text
--]]

local function direction(walk: Targets): (string, string)
	local functions: { [string]: string } = {}
	local entries: { string } = {}
	local readers: { string } = {}

	for _, text: string in walk._functions do
		functions[Pieces.name(text)] = text
	end

	if not walk._server and walk._dictionary then
		table.insert(entries, DICTIONARY)
	end

	for id: number = 1, walk._server and walk._toServer or walk._toClient do
		local row: string? = walk._messages[id]

		if row then
			local reader: string = functions[row:match("read = ([%w_]+)") :: string]
			local read: string = reader:gsub("^local function [%w_]+", "function "):gsub("\n$", "")
			local named: string = row:match(`name = "[^"]*"`) :: string

			table.insert(readers, reader)
			table.insert(entries, `[{id}] = \{\n\t{named},\n\tread = {Blocks.indent(1, read):sub(2)},\n},`)
		end
	end

	local inside: string = #entries == 0 and "{}" or `\{\n{Blocks.indent(1, Blocks.paragraphs(entries))}\n}`

	return `{walk._side} = {inside},`, table.concat(readers, "\n")
end

--[[
    The function reading a packet as its runtime does: any channel byte,
    then the server's handshake when one opens it, or a stamped client's
    stamp, then each message, its id as wide as its direction's ids
--]]

local function reading(walk: Targets): string
	local toServer: number, toClient: number = Sizes.idBytes(walk._toServer), Sizes.idBytes(walk._toClient)
	local width: string = toServer == toClient and `{toServer}` or `server and {toServer} or {toClient}`
	local id: string = toServer == toClient and `buffer.readu{toServer * 8}(packet, cursor)`
		or "width == 2 and buffer.readu16(packet, cursor) or buffer.readu8(packet, cursor)"
	local last: number = #walk._streams
	local lines: { string } = {
		"local function read(server: boolean, player: any, packet: buffer, side: { any })",
		"\tlocal length: number = buffer.len(packet)",
		"\tlocal found = server and messages.server or messages.client",
		`\tlocal width: number = {width}`,
		"\tlocal cursor: number, sideCursor: number = 0, 1",
		"",
	}

	local opening: { string } = last > 0
			and {
				`\tif length < {CHANNEL_BYTES} then`,
				`\t\terror("no channel byte")`,
				`\telseif buffer.readu8(packet, 0) > {last} then`,
				"\t\terror(`unknown channel {buffer.readu8(packet, 0)}`)",
				"\tend",
				"",
				`\tcursor = {CHANNEL_BYTES}`,
				"",
			}
		or {}

	-- Whiteoak TODO: with two-byte ids, an id whose low byte is 0 opening a packet reads as a handshake; check the hash
	local handshake: { string } = {
		`\tif server and cursor + {HANDSHAKE_BYTES} <= length and buffer.readu8(packet, cursor) == 0 then`,
		`\t\truntime:note("Volt handshake", cursor, sideCursor, buffer.readu32(packet, cursor + 1))`,
		`\t\tcursor += {HANDSHAKE_BYTES}`,
		"\tend",
		"",
	}

	local stamp: { string } = walk._file.options.stamp
			and {
				"\tif not server then",
				`\t\tif cursor + {STAMP_BYTES} > length then`,
				`\t\t\terror("shorter than its stamp")`,
				"\t\tend",
				"",
				`\t\truntime:note("Volt stamp", cursor, sideCursor, buffer.readf{STAMP_BYTES * 8}(packet, cursor))`,
				`\t\tcursor += {STAMP_BYTES}`,
				"\tend",
				"",
			}
		or {}

	local loop: { string } = {
		"\twhile cursor < length do",
		"\t\tif cursor + width > length then",
		`\t\t\terror("truncated message id")`,
		"\t\tend",
		"",
		`\t\tlocal id: number = {id}`,
		"\t\tlocal message = found[id]",
		"",
		"\t\tif message == nil then",
		"\t\t\terror(`unknown message {id}`)",
		"\t\tend",
		"",
		"\t\truntime.reading = message.name",
		"\t\tcursor, sideCursor = message.read(player, packet, cursor + width, side, sideCursor, length)",
		`\t\truntime.reading = ""`,
		"\tend",
		"end",
		"",
	}

	for _, part: { string } in { opening, handshake, stamp, loop } do
		table.move(part, 1, #part, #lines + 1, lines)
	end

	return table.concat(lines, "\n")
end

--[[
    What PacketProfiler calls: nil for a remote outside the scope's folder,
    else what the packet holds, read by the server's readers when a player
    comes first, ending in any failure, named for its message or the packet
--]]

local function returned(scope: string): string
	return table.concat({
		"return function (remote: Instance, ...: any): { { Name: string, Arguments: { any } } }?",
		`\tlocal folder: Instance? = ReplicatedStorage:FindFirstChild("{FOLDER}")`,
		`\tlocal scope: Instance? = folder and folder:FindFirstChild("{scope}")`,
		"",
		"\tif scope == nil or remote.Parent ~= scope then",
		"\t\treturn nil",
		"\tend",
		"",
		"\tlocal first: any, second: any, third: any = ...",
		`\tlocal server: boolean = typeof(first) ~= "buffer"`,
		"\tlocal player: any, packet: any, side: any = nil, first, second",
		"",
		"\tif server then",
		"\t\tplayer, packet, side = first, second, third",
		"\tend",
		"",
		`\truntime.calls, runtime.reading = \{}, ""`,
		"",
		"\tlocal ok: boolean, problem: any = pcall(read, server, player, packet, side or {})",
		"",
		"\tif not ok then",
		`\t\tlocal detail: string = (tostring(problem):gsub("^.-:%d+: ", ""))`,
		"\t\truntime:note(#runtime.reading == 0 and `packet: {detail}` or `decode: {runtime.reading}`, 0, 0, detail)",
		"\tend",
		"",
		"\treturn runtime.calls",
		"end",
		"",
	}, "\n")
end

-- The emitter an inspector's two walks share: the modules' own, but for the reads only a runtime resolves
function Inspector.emitter(options: Options): Emit
	return setmetatable(Emit.new(options), Reading) :: any
end

--[[
    The inspector from a schema's server and client walks: the header,
    the types, the stand-in runtime, the pieces the readers reach, each
    direction's readers and what reads a packet. Past FILE_LOCALS it is
    refused at the top of the options file, since it never shards
--]]

function Inspector.module(server: Targets, client: Targets, name: string, diagnostics: Diagnostics): Extra
	local options: Options = server._file.options
	local named: { string } = Types.named(server._file.declarations, {})
	local about: string = table.concat({
		`    The packet inspector Volt {VERSION} generated from {name}: the`,
		`    function PacketProfiler calls for each packet on the {options.scope} scope's`,
		"    remotes, reading every message with the checks its receiving side",
		"    reads with. Generated code: change the schema and run volt again",
		"    rather than editing this file",
	}, "\n")

	server:api()
	client:api()

	local toServer: string, heard: string = direction(server)
	local toClient: string, told: string = direction(client)
	local kept: { string } = Pieces.kept(Pieces.list(server._emitter), `{heard}\n{told}`)
	local messages: string = Blocks.indent(1, Blocks.paragraphs({ toServer, toClient }))

	local parts: { string } =
		{ `--[[\n{about}\n--]]\n\n--!strict\nlocal ReplicatedStorage = game:GetService("ReplicatedStorage")\n` }

	-- Every named type is a local line, since nothing requires the inspector for its types
	for index: number, line: string in named do
		named[index] = (line:gsub("^export ", ""))
	end

	if #named > 0 then
		table.insert(parts, `{table.concat(named, "\n")}\n`)
	end

	table.insert(parts, `{BOT}\n`)
	table.insert(parts, RECORDER)
	table.move(kept, 1, #kept, #parts + 1, parts)
	table.insert(parts, `local messages: {MESSAGES} = \{\n{messages}\n}\n`)
	table.insert(parts, reading(server))
	table.insert(parts, returned(options.scope :: string))

	local text: string = table.concat(parts, "\n")
	local declared: number = Pieces.declared(text)

	if declared > FILE_LOCALS then
		local top: { start: number, finish: number } =
			{ start = diagnostics.source.start, finish = diagnostics.source.start }
		local needs: string = `the inspector needs {declared} module-level locals`
		diagnostics:error("V4003", `{needs}, more than one generated file holds ({FILE_LOCALS})`, top)
	end

	return { output = options.inspectorOutput :: string, text = text }
end

return Inspector
