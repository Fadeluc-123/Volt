--[[
    Every primitive the schema language names, one row each: the bytes it
    takes on the wire, the bounds an integer holds, whether it is a float,
    the steps a quantised float is cut into, and for a wide integer the two
    parts the buffer library carries it as
--]]

--!strict
export type Primitive = {
	bytes: number?, -- Fixed bytes on the wire; none for boolean, unknown, string and buffer
	min: number?, -- The bounds an integer holds; a float has none
	max: number?,
	float: boolean?,
	levels: number?, -- The steps a quantised float's range is cut into
	low: string?, -- A wide integer's low part, as a width the buffer library writes
	high: string?, -- Its high part
	unit: number?, -- What one step of the high part is worth
	half: number?, -- What lifts a signed high part into the unsigned width it is stored in
}

-- The 64-bit integers stop where a Luau number stops being exact
local Primitives: { [string]: Primitive } = {
	u8 = { bytes = 1, min = 0, max = 255 },
	u16 = { bytes = 2, min = 0, max = 65535 },
	u24 = { bytes = 3, min = 0, max = 2 ^ 24 - 1, low = "u8", high = "u16", unit = 256, half = 0 },
	u32 = { bytes = 4, min = 0, max = 2 ^ 32 - 1 },
	u48 = { bytes = 6, min = 0, max = 2 ^ 48 - 1, low = "u16", high = "u32", unit = 65536, half = 0 },
	u64 = { bytes = 8, min = 0, max = 2 ^ 53, low = "u32", high = "u32", unit = 2 ^ 32, half = 0 },

	i8 = { bytes = 1, min = -128, max = 127 },
	i16 = { bytes = 2, min = -32768, max = 32767 },
	i24 = { bytes = 3, min = -2 ^ 23, max = 2 ^ 23 - 1, low = "u8", high = "u16", unit = 256, half = 2 ^ 15 },
	i32 = { bytes = 4, min = -2 ^ 31, max = 2 ^ 31 - 1 },
	i48 = { bytes = 6, min = -2 ^ 47, max = 2 ^ 47 - 1, low = "u16", high = "u32", unit = 65536, half = 2 ^ 31 },
	i64 = { bytes = 8, min = -2 ^ 53, max = 2 ^ 53, low = "u32", high = "u32", unit = 2 ^ 32, half = 2 ^ 31 },

	f16 = { bytes = 2, float = true },
	f32 = { bytes = 4, float = true },
	f64 = { bytes = 8, float = true },

	q8 = { bytes = 1, levels = 255 },
	q16 = { bytes = 2, levels = 65535 },

	boolean = {},
	string = {},
	buffer = {},
	unknown = {},
}

return Primitives
