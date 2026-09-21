--[[
    The handshake packet a hand-written client sends before anything
    else, as the runtime writes it for a generated one: the one id no
    schema uses as a byte, then the hash the server is expected to hold
--]]

--!strict
local HANDSHAKE_ID: number = 0
local HANDSHAKE_BYTES: number = 5 -- The id, then the hash as a u32

return function (hash: number): buffer
	local packet: buffer = buffer.create(HANDSHAKE_BYTES)

	buffer.writeu8(packet, 0, HANDSHAKE_ID)
	buffer.writeu32(packet, 1, hash)

	return packet
end
