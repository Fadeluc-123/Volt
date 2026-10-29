--[[
    The type-family schemas the emitter's tests share, each compiled and
    its events rendered once as one chunk, with what those tests ask of
    them: an event's parameters at their least, a fire of its writer
    caught by pcall, the check that a fire or a read failed as meant, and
    the byte runs no text takes
--]]

--!strict
local fs = require("@lune/fs")

local Suite = require("./Suite")
local Generated = require("./Generated")
local Values = require("./Values")
local Messages = require("@volt/Compiler/Targets/Messages")
local Schema = require("@volt/Compiler/Config/Types/Schema")

type Event = Schema.Event
type Field = Schema.Field
type File = Schema.File

local expect = Suite.expect

-- One type family each, so every golden stays under the cap
local SCHEMAS: { string } = {
	"Numbers",
	"Scalars",
	"Roblox",
	"Frames",
	"Objects",
	"Records",
	"Optionals",
	"Enums",
	"Unions",
	"Choices",
	"Lists",
	"Tables",
	"Text",
	"Literals",
}

local Families = {
	schemas = SCHEMAS,
	files = {} :: { [string]: File }, -- Each schema compiled
	texts = {} :: { [string]: string }, -- Each schema's events as one chunk, which is also its golden

	-- The five ways utf8.len refuses text: a lone continuation byte, a truncated sequence, an overlong, a surrogate,
	-- and a code point past U+10FFFF
	invalid = {
		string.char(0x80),
		string.char(0xE6, 0x97),
		string.char(0xC0, 0x80),
		string.char(0xED, 0xA0, 0x80),
		string.char(0xF4, 0x90, 0x80, 0x80),
	} :: { string },
}

local function byName(schema: string, name: string): Event
	for _, event: Event in Generated.events(Families.files[schema]) do
		if event.name == name then
			return event
		end
	end

	error(`no event {name} in {schema}`)
end

-- Every parameter of an event at its least, as a list the write takes
function Families.least(schema: string, name: string): { any }
	local written: { any } = {}
	for index: number, field: Field in Messages.parameters(byName(schema, name).data) do
		written[index] = Values.valueOf(field.type, "min")
	end
	return written
end

function Families.fire(module: any, schema: string, name: string, written: { any }): (boolean, any)
	return pcall(module[name].write, table.unpack(written, 1, #Messages.parameters(byName(schema, name).data)))
end

function Families.failure(ok: boolean, message: any, expected: string)
	expect(ok).is(false)
	expect(tostring(message):find(expected, 1, true) ~= nil).is(true)
end

for _, name: string in SCHEMAS do
	Families.files[name] = Generated.compile(name, fs.readFile(`tests/Schemas/{name}.volt`))
	Families.texts[name] = Generated.render(Families.files[name])
end

return Families
