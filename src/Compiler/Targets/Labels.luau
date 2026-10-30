--[[
    The MicroProfiler labels of a module compiled with profileLabels, each
    opening with the scope's label: a reader's, named for its message,
    opened as its first statement and closed once its tail returns, and
    the API's flush around the runtime's; given no label, nothing changes
--]]

--!strict
local Labels = {}

local Blocks = require("../Blocks")

type Block = Blocks.Block

-- Opens each reader's label ahead of whatever it opens with already, named for the message it reads
function Labels.open(label: string?, ...: Block)
	if not label then
		return
	end

	for _, read: Block in { ... } do
		local begin: string = `debug.profilebegin("{label} {read.path}")`
		read.head = read.head and `{begin}\n{read.head}` or begin
	end
end

--[[
    A reader's last statement, from its tail's call: that call returned,
    or under a label the cursors it returns kept, the label closed and the
    cursors returned, so nothing that can raise sits outside the label
--]]

function Labels.close(label: string?, tail: string): string
	if not label then
		return `return runtime:{tail}`
	end

	return `cursor, sideCursor = runtime:{tail}\ndebug.profileend()\nreturn cursor, sideCursor`
end

-- The statements of the API's flush: the runtime's flush, under a label its own when the module labels
function Labels.flush(label: string?): ...string
	if not label then
		return "runtime:flush()"
	end

	return `debug.profilebegin("{label} flush")`, "runtime:flush()", "debug.profileend()"
end

return Labels
