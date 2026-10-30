--[[
    Proves the emitter's writers: every event of every family renders to
    its golden file, reads back what was written at its bounds and at
    random, and refuses a bad value, text that is not UTF-8 among them;
    with validation off only the checks that keep a packet whole are
    left, and every global called is reserved
--]]

--!strict
local fs = require("@lune/fs")

local Suite = require("./Suite")
local Environment = require("./Environment")
local Families = require("./Families")
local Generated = require("./Generated")
local golden = require("./Expected")
local Refusals = require("./Refusals")
local Values = require("./Values")
local Messages = require("@volt/Compiler/Targets/Messages")
local Reserved = require("@volt/Compiler/Config/Reserved")
local Schema = require("@volt/Compiler/Config/Types/Schema")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Event = Schema.Event
type Field = Schema.Field

local Instance = Environment.Instance

local ROUNDS: number = 200 -- Random values written and read back per event
local SCHEMAS: string = "tests/Schemas"
local EXACT_BYTES: number = 4 -- What Text's exact takes, which every invalid run is padded to so each place takes it
local FREE_CHARACTERS: number = 100 -- Four-byte characters in a long free text
local SUN: string = utf8.char(0x65E5) -- One character of three bytes
local FOUR: string = utf8.char(0x1F600) -- One character of four bytes, as long as Text's short and exact take
local NUL: string = string.char(0)

-- A call not reached through a dot or a colon is of a global or a local, and so is the library a call is reached through
local CALLED: { string } = { "[^%w_.:]([%a_][%w_]*)%(", "[^%w_.:]([%a_][%w_]*)%.[%a_][%w_]*%(" }

-- Every place Text's writers take text: the event, the parameter, the path a refusal names and how it is carried
local TEXTS: { { any } } = {
	{ "Text", 1, "Text.short", "value" },
	{ "Text", 2, "Text.exact", "value" },
	{ "Text", 3, "Text.free", "value" },
	{ "Notes", 1, "Notes.tags[key]", "key" },
	{ "Notes", 2, "Note.title", "title" },
	{ "Notes", 3, "Note.body", "body" },
}

local valueOf = Values.valueOf
local near = Values.near
local least = Families.least
local fire = Families.fire
local failure = Families.failure

-- A text as a row of TEXTS carries it: as the value, as a map's one key, or as one field of a note whose other is valid
local function placed(how: string, text: string): any
	if how == "value" then
		return text
	elseif how == "key" then
		return { [text] = 1 }
	end

	local note: { [string]: string } = { title = "a", body = "" }
	note[how] = text
	return note
end

describe("Emit", function ()
	for _, schema: string in Families.schemas do
		describe(schema, function ()
			local text: string = Families.texts[schema]

			test("renders as the golden file", function ()
				expect(golden(`tests/Golden/{schema}`, "Emit", text)).is(text)
			end)

			describe("round trips", function ()
				local module: any, packet: () -> (buffer, { any }) = Generated.load(schema, text)

				for _, event: Event in Generated.events(Families.files[schema]) do
					test(event.name, function ()
						local fields: { Field } = Messages.parameters(event.data)

						for round: number = 0, ROUNDS do
							local ends: string? = round == 0 and "min" or round == 1 and "max" or nil
							local written: { any } = {}

							for index: number, field: Field in fields do
								written[index] = valueOf(field.type, ends)
							end

							module[event.name].write(table.unpack(written, 1, #fields))

							local bytes: buffer, side: { any } = packet()
							local read: { any } = { module[event.name].read(bytes, 0, side, 1, buffer.len(bytes)) }

							expect(read[1]).is(buffer.len(bytes))
							expect(read[2]).is(#side + 1)

							for index: number, field: Field in fields do
								local message: string =
									`{event.name}.{field.name}: wrote {written[index]}, read {read[index + 2]}`
								assert(near(field.type, written[index], read[index + 2]), message)
							end
						end
					end)
				end
			end)

			describe("writers refuse", function ()
				local module: any = Generated.load(schema, text)

				for _, row: { any } in Refusals[schema] do
					test(row[4], function ()
						local written: { any } = least(schema, row[1])
						written[row[2]] = row[3]

						local ok: boolean, message: any = fire(module, schema, row[1], written)
						failure(ok, message, row[4])
					end)
				end
			end)
		end)
	end

	describe("a refusal", function ()
		test("leaves nothing of the message behind, neither bytes nor slots", function ()
			local module: any, packet: () -> (buffer, { any }) = Generated.load("Objects", Families.texts.Objects)
			local written: { any } = least("Objects", "Objects")

			written[2] = Instance.new("Folder")
			expect((fire(module, "Objects", "Objects", written))).is(false)

			local bytes: buffer, side: { any } = packet()
			expect(buffer.len(bytes)).is(0)
			expect(#side).is(0)
		end)
	end)

	describe("text", function ()
		local module: any, packet: () -> (buffer, { any }) = Generated.load("Text", Families.texts.Text)

		test("round-trips empty, at its exact and its longest length, as four-byte characters and with NUL", function ()
			-- Short, exact and free: three bytes in one character first, then each at its longest, then NUL
			local rows: { { string } } = {
				{ SUN, FOUR, "" },
				{ FOUR, string.rep(NUL, EXACT_BYTES), string.rep(FOUR, FREE_CHARACTERS) },
				{ NUL, `a{NUL}b{NUL}`, NUL },
			}

			for _, written: { string } in rows do
				module.Text.write(table.unpack(written))

				local bytes: buffer, side: { any } = packet()
				local read: { any } = { module.Text.read(bytes, 0, side, 1, buffer.len(bytes)) }

				expect(`{read[3]}|{read[4]}|{read[5]}`).is(table.concat(written, "|"))
			end
		end)

		for _, row: { any } in TEXTS do
			test(`{row[3]} refuses each way text is not UTF-8`, function ()
				for _, run: string in Families.invalid do
					local written: { any } = least("Text", row[1])
					written[row[2]] = placed(row[4], `{string.rep("a", EXACT_BYTES - #run)}{run}`)

					local ok: boolean, message: any = fire(module, "Text", row[1], written)
					failure(ok, message, `{row[3]}: invalid UTF-8`)
				end
			end)
		end
	end)

	describe("with write validation off", function ()
		local loose: { [string]: any } = {}
		local checks: { [string]: number } = {}

		-- How many writers in a chunk still refuse a value by its Luau type; readers and union dispatch may ask
		local function typeChecks(text: string): number
			local found: number = 0
			for body: string in text:gmatch("local function write.-\nend\n") do
				found += body:find('type%a*%b() ~= "') and 1 or 0
			end
			return found
		end

		for _, schema: string in Families.schemas do
			local source: string = `option writeValidation = false\n{fs.readFile(`tests/Schemas/{schema}.volt`)}`
			local text: string = Generated.render((Generated.compile(schema, source)))

			loose[schema] = Generated.load(schema, text)
			checks[schema] = typeChecks(text)
		end

		test("no writer checks a value's type or range", function ()
			local written: { any } = least("Numbers", "Integers")
			written[1] = 0.5
			written[2] = 1000

			for _, schema: string in Families.schemas do
				expect(checks[schema]).is(0)
			end

			expect((fire(loose.Numbers, "Numbers", "Integers", written))).is(true)
		end)

		test("a length outside its bounds is still refused", function ()
			local written: { any } = least("Scalars", "Bytes")
			written[1] = string.rep("x", 33)

			local ok: boolean, message: any = fire(loose.Scalars, "Scalars", "Bytes", written)
			failure(ok, message, "Bytes.name: length out of range")
		end)

		test("a nil instance is still refused", function ()
			local written: { any } = least("Objects", "Objects")
			written[1] = nil

			local ok: boolean, message: any = fire(loose.Objects, "Objects", "Objects", written)
			failure(ok, message, "Objects.a: expected Instance")
		end)

		test("a value no variant or member can carry is still refused", function ()
			local written: { any } = least("Enums", "Enums")
			written[1] = "Green"

			local ok: boolean, message: any = fire(loose.Enums, "Enums", "Enums", written)
			failure(ok, message, "Team: expected enum { Red, Blue }")

			written = least("Unions", "Unions")
			written[1] = {}
			ok, message = fire(loose.Unions, "Unions", "Unions", written)
			failure(ok, message, "Unions.a: expected u8 | string(0..4) | boolean")
		end)
	end)

	test("reserves every global a generated function calls, so no field or parameter local shadows one", function ()
		local reserved: { [string]: boolean } = {}
		local texts: { { schema: string, text: string } } = {}
		local unreserved: { string } = {}
		local utf8In: { [string]: boolean } = {} -- The schemas whose modules call the utf8 library

		for _, name: string in Reserved.generated do
			reserved[name] = true
		end

		for _, schema: string in Families.schemas do
			table.insert(texts, { schema = schema, text = Families.texts[schema] })
		end

		for _, name: string in fs.readDir(SCHEMAS) do
			local schema: string? = name:match("^(.+)%.volt$")
			if schema then
				local client: string, server: string = Generated.modules(schema, fs.readFile(`{SCHEMAS}/{name}`))
				table.insert(texts, { schema = schema, text = client })
				table.insert(texts, { schema = schema, text = server })
			end
		end

		for _, entry in texts do
			-- Comments and strings call nothing, and a name the text declares is its own
			local code: string =
				entry.text:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", ""):gsub("\\.", ""):gsub('"[^"]*"', "")
			local declared: { [string]: boolean } = {}

			for name: string in code:gmatch("local ([%a_][%w_]*)") do
				declared[name] = true
			end
			for name: string in code:gmatch("local function ([%a_][%w_]*)") do
				declared[name] = true
			end

			for _, pattern: string in CALLED do
				for name: string in (`\n{code}`):gmatch(pattern) do
					utf8In[entry.schema] = utf8In[entry.schema] or name == "utf8"

					if not declared[name] and not reserved[name] and not table.find(unreserved, name) then
						table.insert(unreserved, name)
					end
				end
			end
		end

		expect(table.concat(unreserved, ", ")).is("")
		expect(reserved.utf8 and utf8In.Text and utf8In.Console).is(true)
	end)
end)
