--[[
    Holds every message to the packet it travels in: an unreliable event to
    one fire of the budget, and a reliable message a client sends to the
    frame the server reads beside the handshake, each counting what the
    schema's packets open with before their messages
--]]

--!strict
local Packets = {}

local Diagnostics = require("../Diagnostics")
local Schema = require("../Config/Types/Schema")
local Sizes = require("./Sizes")
local Wire = require("../Config/Wire")

type Declaration = Schema.Declaration
type Diagnostics = Diagnostics.Diagnostics
type Event = Schema.Event
type Options = Schema.Options
type Pack = Schema.Pack
type Size = Sizes.Size
type Type = Schema.Type

-- The last id analysis gave each way and how many channels the schema declares, once every declaration is walked
export type Counts = { toServer: number, toClient: number, channels: number }

local SLOT_BYTES: number = Wire.slotBytes
local STATUS_BYTES: number = Wire.statusBytes
local HANDSHAKE_BYTES: number = Wire.handshakeBytes
local SEQUENCE_BYTES: number = Wire.sequenceBytes
local STAMP_BYTES: number = Wire.stampBytes
local CHANNEL_BYTES: number = Wire.channelBytes

-- The most a refusal's reason takes, its length prefix included, by the length rule the runtime follows
local REASON_PREFIX: number, _: number, REASON_MAX: number =
	Sizes.lengths({ min = 0, max = Wire.replyMessage, start = 0, finish = 0 })

--[[
    Refuses every unreliable event whose largest message would not fit one
    fire: its id and an ordered event's sequence, with the stamp a server
    packet opens with in a stamped schema and the channel byte every packet
    opens with in a schema that declares a channel
--]]

function Packets.budget(diagnostics: Diagnostics, events: { Event }, counts: Counts, options: Options)
	local budget: number = options.unreliableBudget :: number

	for _, event: Event in events do
		local toServer: number = event.toServer and counts.toServer or 0
		local toClient: number = event.toClient and counts.toClient or 0
		local payload: Size = event.data and Sizes.size(event.data) or Sizes.fixed(0)
		local largest: number = Sizes.idBytes(math.max(toServer, toClient)) + select(2, Sizes.block(payload))
		local opening: { string } = {}

		if event.type == "OrderedUnreliable" then
			largest += SEQUENCE_BYTES
		end

		-- A client's packets carry no stamp, so only an event the server sends pays for it
		if options.stamp and event.toClient then
			largest += STAMP_BYTES
			table.insert(opening, `the {STAMP_BYTES}-byte stamp`)
		end

		if counts.channels > 0 then
			largest += CHANNEL_BYTES
			table.insert(opening, "the channel byte")
		end

		if largest > budget then
			local with: string = #opening > 0 and ` with {table.concat(opening, " and ")}` or ""
			local message: string =
				`event {event.path} can reach {largest} bytes{with}, over the unreliable budget of {budget}`
			diagnostics:error("V3010", message, event.spans.type)
		end
	end
end

--[[
    Refuses every reliable message a client sends whose largest size, its
    id and a call's slot included, would take the frame the handshake
    opens, after the channel byte in a schema that declares a channel, past
    maxPacket, since the server drops a packet that long whole. A from:
    Server function's client sends its reply: the slot, the status and the
    larger of its returns and a refusal's reason
--]]

function Packets.frame(diagnostics: Diagnostics, messages: { Declaration }, counts: Counts, options: Options)
	local maxPacket: number = options.maxPacket :: number
	local idBytes: number = Sizes.idBytes(counts.toServer)
	local channelled: boolean = counts.channels > 0
	local opening: number = HANDSHAKE_BYTES + (channelled and CHANNEL_BYTES or 0)
	local beside: string = `the {HANDSHAKE_BYTES}-byte handshake{channelled and " and the channel byte" or ""}`

	for _, declaration: Declaration in messages do
		local call: boolean = declaration.kind == "function"
		local reply: boolean = call and (declaration :: any).from == "Server"
		local data: (Type | Pack)? = (declaration :: any)[reply and "return" or "data"]
		local payload: Size = data and Sizes.size(data) or Sizes.fixed(0)
		local most: number = select(2, Sizes.block(payload))
		local largest: number = idBytes + (call and SLOT_BYTES or 0) + most

		if reply then
			largest = idBytes + SLOT_BYTES + STATUS_BYTES + math.max(most, REASON_PREFIX + REASON_MAX)
		end

		if largest + opening > maxPacket then
			local sent: string = reply and "reply" or "call"
			local named: string = call and `function {declaration.path}'s {sent}` or `event {declaration.path}`
			local message: string = `{named} can reach {largest} bytes, over maxPacket {maxPacket} with {beside}`
			diagnostics:error("V3012", message, declaration)
		end
	end
end

return Packets
