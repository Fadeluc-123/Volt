--[[
    Runs the benchmark: compiles the schema for every library, builds
    the place, runs it in Studio through run-in-roblox and writes the
    report the place prints to benchmark/Results.md with the size of
    every generated module beneath it. --build stops once the place is
    built
--]]

--!strict
local datetime = require("@lune/datetime")
local fs = require("@lune/fs")
local process = require("@lune/process")

local FOLDER: string = "benchmark"
local GENERATED: string = `{FOLDER}/Generated`
local PLACE: string = `{FOLDER}/Benchmark.rbxl`
local RESULTS: string = `{FOLDER}/Results.md`
local MARKER: string = "--VOLT BENCHMARK--"
local KILOBYTE: number = 1024
local LIBRARIES: { string } = { "Blink", "Zap", "ZapUnchecked", "Volt", "VoltUnchecked" }

type Variant = { source: string, derived: string, from: string, to: string, options: string }
type Compile = { program: string, arguments: { string } }

-- Each library's checks flipped from its default, written from the same definition under another output folder and remote scope
local VARIANTS: { Variant } = {
	{
		source = "Definition.zap",
		derived = "ZapUnchecked.zap",
		from = "Generated/Zap/",
		to = "ZapUnchecked/",
		options = `opt write_checks = false\nopt remote_scope = "UNCHECKED"\n`,
	},
	{
		source = "Definition.volt",
		derived = "VoltUnchecked.volt",
		from = "Generated/Volt/",
		to = "VoltUnchecked/",
		options = `option writeValidation = false\noption scope = VoltUnchecked\n`,
	},
}

local COMPILES: { Compile } = {
	{ program = "zap", arguments = { `{FOLDER}/Definition.zap` } },
	{ program = "zap", arguments = { `{GENERATED}/ZapUnchecked.zap` } },
	{ program = "blink", arguments = { `{FOLDER}/Definition.blink`, "--yes" } },
	{ program = "lune", arguments = { "run", "src/Compiler", `{FOLDER}/Definition.volt` } },
	{ program = "lune", arguments = { "run", "src/Compiler", `{GENERATED}/VoltUnchecked.volt` } },
}

-- Runs one tool with its output forwarded, and stops at the first that fails
local function run(program: string, arguments: { string })
	local result = process.exec(program, arguments, { stdio = "forward" })

	if not result.ok then
		process.exit(result.code)
	end
end

-- What a tool is pinned at, or what the package is versioned as: the quoted value, minus the owner and tool a pin starts with
local function version(manifest: string, key: string): string
	local value: string = fs.readFile(manifest):match(`\n{key} = "([^"]+)"`) or "?"

	return (value:gsub("^[^@]*@", ""))
end

-- A generated module's size, as its bytes and lines
local function size(path: string): string
	local text: string = fs.readFile(path)
	local lines: number = select(2, text:gsub("\n", ""))

	return string.format("%.1f KB, %d lines", #text / KILOBYTE, lines)
end

for _, library: string in LIBRARIES do
	local folder: string = `{GENERATED}/{library}`

	if not fs.isDir(folder) then
		fs.writeDir(folder)
	end
end

for _, variant: Variant in VARIANTS do
	local definition: string = fs.readFile(`{FOLDER}/{variant.source}`)
	local redirected: string = definition:gsub(variant.from, variant.to)

	fs.writeFile(`{GENERATED}/{variant.derived}`, `{variant.options}{redirected}`)
end

for _, compile: Compile in COMPILES do
	run(compile.program, compile.arguments)
end

run("rojo", { "build", `{FOLDER}/benchmark.project.json`, "-o", PLACE })

if table.find(process.args, "--build") then
	return
end

-- run-in-roblox writes its plugin into Studio's local plugins folder and panics when the folder is missing; a run that
-- was killed leaves its plugin there for every later Studio to load, so stale ones go first
local plugins: string = `{process.env.LOCALAPPDATA}/Roblox/Plugins`

if not fs.isDir(plugins) then
	fs.writeDir(plugins)
end

for _, name: string in fs.readDir(plugins) do
	if name:match("^run_in_roblox") then
		fs.removeFile(`{plugins}/{name}`)
	end
end

-- Studio's output is captured rather than forwarded, since Lune's forward mode shows a child's output without keeping it;
-- the Output window in Studio shows the run as it goes
print("Press F5 in the Studio that opens; the report comes back here when the play session ends")

local studio = process.exec(
	"run-in-roblox",
	{ "--place", PLACE, "--script", `{FOLDER}/Run.luau` },
	{ stdio = "default" }
)
local output: string = `{studio.stdout}{studio.stderr}`

if not studio.ok then
	print(output)
	process.exit(studio.code)
end

local at: number? = output:find(MARKER, 1, true)

assert(at, "Studio printed no report")

-- The script runs once per Studio instance, so the report may be printed twice; the first copy is the one
local from: number = at + #MARKER
local again: number? = output:find(MARKER, from, true)

local sizes: { string } = { "## Generated modules\n", "| Library | Client | Server |", "|---|---|---|" }

for _, library: string in LIBRARIES do
	table.insert(
		sizes,
		`| {library} | {size(`{GENERATED}/{library}/Client.luau`)} | {size(`{GENERATED}/{library}/Server.luau`)} |`
	)
end

local ran: string = datetime.now():formatUniversalTime("%Y-%m-%d")
local pins: string = `zap {version("rokit.toml", "zap")}, blink {version("rokit.toml", "blink")}, volt {version(
	"wally.toml",
	"version"
)}`
local report: string = output:sub(from, again and again - 1 or nil):gsub("^%s+", ""):gsub("%s+$", "")

fs.writeFile(RESULTS, `# Volt benchmark\n\nRun {ran} with {pins}.\n{report}\n\n{table.concat(sizes, "\n")}\n`)
print(`Wrote {RESULTS}`)
