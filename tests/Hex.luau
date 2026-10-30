--[[
    A packet's bytes as upper-case hex pairs with a space between, the way
    the design writes a packet out, so a test compares what was sent with
    the worked example byte for byte
--]]

--!strict
return function (packet: buffer): string
	local bytes: { string } = {}

	for index: number = 0, buffer.len(packet) - 1 do
		table.insert(bytes, string.format("%02X", buffer.readu8(packet, index)))
	end

	return table.concat(bytes, " ")
end
