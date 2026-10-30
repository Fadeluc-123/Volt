--[[
    Proves a recursive type's size: that of its deepest, widest value by
    each type's own bound, held to the budget and the packet as any type's
    is, and taken in one walk per type and level however it branches
--]]

--!strict
local Suite = require("./Suite")
local compiled = require("./Compiled")
local rendered = require("./Rendered")
local Schema = require("@volt/Compiler/Config/Types/Schema")
local Sizes = require("@volt/Compiler/Analyse/Sizes")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type TypeDeclaration = Schema.TypeDeclaration

-- The two options every schema must carry, so a fragment compiles clean
local HEADER: string = `option clientOutput = "Client.luau"\noption serverOutput = "Server.luau"\n`

local TREE: string = "struct Tree { name: string(0..8), kids: Tree[0..3] }\n"
local DEEP: string = `@depth(4) {TREE}`

local function report(text: string): string
	local diagnostics = select(2, compiled(text))
	return diagnostics:render()
end

-- What a reference to a file's nth declaration takes, as a message holding it at level 1 sees it
local function sized(file: Schema.File, index: number): Sizes.Size
	local target: TypeDeclaration = file.declarations[index] :: TypeDeclaration
	return Sizes.size({ kind = "reference", name = target.name, target = target, start = 0, finish = 0 })
end

describe("Cycle sizes", function ()
	test("Tree at @depth(4) sizes 2..400 bytes", function ()
		local file: Schema.File, diagnostics = compiled(`{HEADER}{DEEP}`)
		local size: Sizes.Size = sized(file, 1)

		expect(diagnostics:render()).is("")
		expect(size.min).is(2)
		expect(size.max).is(400)
		expect(size.bits).is(0)
	end)

	test("V3012 refuses Tree in a client's event at the default depth, 215,233,601 bytes", function ()
		local text: string = `{HEADER}{TREE}event Scene \{ from: Client, type: Reliable, call: SingleSync, data: Tree }`
		local message: string =
			"error V3012: event Scene can reach 215233601 bytes, over maxPacket 8192 with the 5-byte handshake"

		expect(report(text)).is(rendered(text, "Scene", message))
	end)

	test("a @depth small enough lets the same event through", function ()
		local text: string = `{HEADER}{DEEP}event Scene \{ from: Client, type: Reliable, call: SingleSync, data: Tree }`

		expect(report(text)).is("")
	end)

	test("V3010 holds a recursive type to the unreliable budget, and a bounded one fits it", function ()
		local fits: string =
			`{HEADER}@depth(4) struct Cell \{ value: u8, next: Cell? }\nevent E \{ from: Client, type: Unreliable, call: SingleSync, data: Cell }`
		local over: string = `{HEADER}{TREE}event E \{ from: Server, type: Unreliable, call: SingleSync, data: Tree }`

		expect(report(fits)).is("")
		expect(report(over):find("error V3010", 1, true) ~= nil).is(true)
	end)

	test("each type holds to its own bound, every member of a cycle counting a level", function ()
		local tight: string = `{HEADER}@depth(2) struct A \{ b: B? }\n@depth(9) struct B \{ a: A? }`
		local loose: string = `{HEADER}@depth(3) struct A \{ b: B? }\n@depth(9) struct B \{ a: A? }`

		-- Level 1 is an A, level 2 a B, level 3 an A only where A's bound allows it
		expect(sized((compiled(tight)), 1).max).is(2)
		expect(sized((compiled(loose)), 1).max).is(4)
	end)

	test("a shared type that is not recursive starts what it holds over at level 1", function ()
		local text: string =
			`{HEADER}@depth(2) struct T \{ kids: T[0..2] }\nstruct Mid \{ t: T }\nstruct Top \{ one: Mid, two: Mid }`
		local file: Schema.File, diagnostics = compiled(text)

		expect(diagnostics:render()).is("")
		expect(sized(file, 2).max).is(sized(file, 1).max)
		expect(sized(file, 3).max).is(2 * sized(file, 1).max)
	end)

	test("a member of a cycle with no @depth of its own counts a level and takes the default", function ()
		local text: string = `{HEADER}@depth(2) struct T \{ via: Via? }\nstruct Via \{ t: T? }`
		local file: Schema.File, diagnostics = compiled(text)

		-- T at level 1, Via at 2, and T past its bound at 3
		expect(diagnostics:render()).is("")
		expect((file.declarations[2] :: TypeDeclaration).depth).is(16)
		expect(sized(file, 1).max).is(2)
	end)

	test("an inlined type that is no member of a cycle keeps the level its holder gave it", function ()
		local text: string =
			`{HEADER}@depth(2) struct T \{ kids: T[0..2], via: Via }\nstruct Via \{ x: u8, other: Other? }\n@depth(2) struct Other \{ next: Other? }`
		local file: Schema.File, diagnostics = compiled(text)
		local via: TypeDeclaration = file.declarations[2] :: TypeDeclaration

		-- Other at level 2 holds only itself past its bound, and at level 3 is past it already
		expect(diagnostics:render()).is("")
		expect(Sizes.size(via.type, 2).max).is(2)
		expect(Sizes.size(via.type, 3).max).is(1)
	end)

	test("a branching type at the most depth costs one walk per level, and never the call limit", function ()
		local text: string = `{HEADER}@depth(1000) struct T \{ a: T?, b: T?, c: T?, d: T? }`
		local file: Schema.File, diagnostics = compiled(text)

		expect(diagnostics:render()).is("")
		expect(sized(file, 1).min).is(1)
	end)

	test("two compiles in one process size each their own tree", function ()
		local first: Schema.File = compiled(`{HEADER}@depth(2) {TREE}`)
		local second: Schema.File = compiled(`{HEADER}@depth(3) {TREE}`)

		expect(sized(first, 1).max).is(40)
		expect(sized(second, 1).max).is(130)
	end)
end)
