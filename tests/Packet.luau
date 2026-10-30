--[[
    A packet built by hand from a flat list of bytes, as a tampered or
    hand-written side sends one past the generated writers, so a test
    names every byte the wire carries
--]]

--!strict
return function (bytes: { number }): buffer
	local out: buffer = buffer.create(#bytes)

	for index: number, byte: number in bytes do
		buffer.writeu8(out, index - 1, byte)
	end

	return out
end
