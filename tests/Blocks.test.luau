--[[
    Proves the block builder hands out constant offsets, unique locals
    and flag bits, stores flag bytes at every width, lands a child's lines
    in its parent's tail inside the scope opened around it, sets apart the
    statements that span lines, and refuses a block whose claimed flag
    bits differ from those it reserved or whose scope was left open
--]]

--!strict
local Suite = require("./Suite")
local Blocks = require("@volt/Compiler/Blocks")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Block = Blocks.Block

-- The text a block renders as, one line per argument
local function lines(...: string): string
	return `{table.concat({ ... }, "\n")}\n`
end

describe("Blocks", function ()
	test("reserves bytes at constant offsets on both sides", function ()
		local write: Block = Blocks.new("write", "Test")
		local read: Block = Blocks.new("read", "Test")

		expect(write:at(write:reserve(1))).is("offset")
		expect(write:at(write:reserve(2))).is("offset + 1")
		expect(read:at(read:reserve(4))).is("cursor")
		expect(read:at(read:reserve(1))).is("cursor + 4")
	end)

	test("names locals uniquely and never as what the generated code already uses", function ()
		local block: Block = Blocks.new("read", "Test")

		expect(block:name("dir")).is("dir")
		expect(block:name("dir")).is("dir_2")
		expect(block:name("cursor")).is("cursor_2")
		expect(block:child():name("dir")).is("dir_3")
	end)

	test("allocates once at the top and stores the flags after the fields", function ()
		local write: Block = Blocks.new("write", "Test")

		write:flags(9)
		write:line("a")

		local word: string, bit: number = write:flag()
		expect(word).is("flags")
		expect(bit).is(0)
		expect(select(2, write:flag(8))).is(1)

		expect(write:done()).is(
			lines(
				"\tlocal offset: number, out: buffer = allocate(2)",
				"\tlocal flags: number = 0",
				"\ta",
				"\tbuffer.writeu16(out, offset, flags)"
			)
		)
	end)

	test("checks once at the top, reads the flags and steps the cursor before the tail", function ()
		local read: Block = Blocks.new("read", "Test")

		read:flags(20)
		read:reserve(1)
		read:line("a")
		read:tail("b")
		read:flag(20)

		expect(read:done()).is(
			lines(
				"\tif cursor + 4 > length then",
				'\t\terror("Test: truncated")',
				"\tend",
				"",
				"\tlocal flags: number = buffer.readu16(packet, cursor) + buffer.readu8(packet, cursor + 2) * 65536",
				"\ta",
				"\tcursor += 4",
				"\tb"
			)
		)
	end)

	test("spreads more than thirty-two flag bits over words", function ()
		local write: Block = Blocks.new("write", "Test")

		write:flags(40)
		for _ = 1, 40 do
			write:flag()
		end

		expect(write:done()).is(
			lines(
				"\tlocal offset: number, out: buffer = allocate(5)",
				"\tlocal flags: number = 0",
				"\tlocal flags_2: number = 0",
				"\tbuffer.writeu32(out, offset, flags)",
				"\tbuffer.writeu8(out, offset + 4, flags_2)"
			)
		)
	end)

	test("sets a statement that spans lines apart from its neighbours", function ()
		local write: Block = Blocks.new("write", "Test")

		write:line("a")
		write:line("if x then\n\tb\nend")
		write:line("c")
		write:line("d")

		expect(write:done()).is(lines("\ta", "", "\tif x then", "\t\tb", "\tend", "", "\tc", "\td"))
	end)

	test("closes with a final statement in a paragraph of its own", function ()
		local read: Block = Blocks.new("read", "Test")

		read:line("a")

		expect(read:done("return cursor")).is(lines("\ta", "", "\treturn cursor"))
		expect(Blocks.new("read", "Test"):done("return cursor")).is(lines("\treturn cursor"))
	end)

	test("lands a child's lines in the parent's tail inside the scope opened around it", function ()
		local write: Block = Blocks.new("write", "Test")
		local child: Block = write:child()

		write:line("parent")
		write:open("if present then")
		child:reserve(1)
		child:line("child")
		child:done()
		write:close("end")

		expect(write:done()).is(
			lines(
				"\tparent",
				"",
				"\tif present then",
				"\t\tlocal offset_2: number, out_2: buffer = allocate(1)",
				"\t\tchild",
				"\tend"
			)
		)
	end)

	test("extends a block with a payload the allocator or the packet must hold", function ()
		local write: Block = Blocks.new("write", "Test")
		local read: Block = Blocks.new("read", "Test")
		local function payload(target: string, offset: string): string
			return `use {target} at {offset}`
		end

		write:extend("name", "Test.name", "#name", payload)
		read:extend("name", "Test.name", "nameLength", payload)

		expect(write:done()).is(
			lines("\tlocal nameOffset: number, nameOut: buffer = allocate(#name)", "\tuse nameOut at nameOffset")
		)
		expect(read:done()).is(
			lines(
				"\tif cursor + nameLength > length then",
				'\t\terror("Test.name: truncated")',
				"\tend",
				"",
				"\tuse packet at cursor",
				"\tcursor += nameLength"
			)
		)
	end)

	test("fills a region the parent took or checked with no line of its own", function ()
		local write: Block = Blocks.new("write", "Test")
		local read: Block = Blocks.new("read", "Test")
		local writeChild: Block = write:child("Test", write:region("items", "Test.items", "4 * #items"))
		local readChild: Block = read:child("Test", read:region("items", "Test.items", "4 * count"))

		write:open("for")
		read:open("for")
		writeChild:reserve(4)
		writeChild:line("child")
		readChild:reserve(4)
		readChild:line("child")
		writeChild:done()
		readChild:done()
		write:close("end")
		read:close("end")

		expect(write:done()).is(
			lines(
				"\tlocal itemsOffset: number, itemsOut: buffer = allocate(4 * #items)",
				"",
				"\tfor",
				"\t\tchild",
				"\t\titemsOffset += 4",
				"\tend"
			)
		)
		expect(read:done()).is(
			lines(
				"\tif cursor + 4 * count > length then",
				'\t\terror("Test.items: truncated")',
				"\tend",
				"",
				"\tfor",
				"\t\tchild",
				"\t\tcursor += 4",
				"\tend"
			)
		)
	end)

	test("refuses a block whose claimed bits differ from those reserved", function ()
		local write: Block = Blocks.new("write", "Test")

		write:flags(2)
		write:flag()

		local ok: boolean, message: any = pcall(write.done, write)
		expect(ok).is(false)
		expect(tostring(message):find("Test: 1 flag bits claimed of 2 reserved", 1, true) ~= nil).is(true)
	end)

	test("refuses a block whose scope was left open", function ()
		local write: Block = Blocks.new("write", "Test")

		write:open("if x then")

		local ok: boolean, message: any = pcall(write.done, write)
		expect(ok).is(false)
		expect(tostring(message):find("Test: a scope was left open", 1, true) ~= nil).is(true)
	end)
end)
