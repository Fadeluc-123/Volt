option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

-- Each value travels as a 2-byte id, its string sent to a player once, ahead of the first packet that could name it
@dictionary type Item = string(1..32)
@dictionary type Title = string.utf8(0..24)

struct Slot { title: Title, count: u8 }

event picked {
	from: Server, type: Reliable, call: ManySync,
	data: (item: Item, title: Title),
}

event stock {
	from: Server, type: Reliable, call: SingleAsync,
	data: { [Item]: Slot }(0..16),
}

-- The server writes the reply, so a function's return may name one where its data may not
function lookup {
	data: u16,
	return: Item?,
}
