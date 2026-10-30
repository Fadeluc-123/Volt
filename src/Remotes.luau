--[[
    The real transport: the remotes under ReplicatedStorage.Volt.<scope>,
    found or created by the server and awaited by the client, the instance
    ids beside them, the frame, the players and their signals, the clock,
    the VM's hub; the one file in the runtime that touches the DataModel.
    Outside a running game it is a transport that drops every packet
--]]

--!strict
local Config = require("./Config/Runtime")
local Hub = require("./Hub")
local Types = require("./Config/Types/Runtime")

type Handler = Types.Handler
type Hub = Hub.Hub
type Spawn = Types.Spawn
type Transport = Types.Transport

local FOLDER: string = Config.folder
local RELIABLE: string = Config.reliable
local UNRELIABLE: string = Config.unreliable
local REFERENCES: string = Config.references
local COUNTER: string = Config.counter
local WAIT_SECONDS: number = Config.waitSeconds

local Remotes = {}

local Shared: Hub? = nil -- The VM's hub, made at the first server open or bot call; nothing else here keeps state

-- What every fire, connection and signal of the transport does outside a running game
local function nothing() end

local function nobody(): { any }
	return {}
end

local function never(): number
	return 0
end

local function absent(): Instance?
	return nil
end

-- The server's clock, which a stamped server's packets carry
local function now(): number
	return workspace:GetServerTimeNow()
end

-- Connects a callback to every frame and returns what disconnects it, as the hub takes it
local function connect(callback: () -> ()): () -> ()
	local connection: RBXScriptConnection = game:GetService("RunService").Heartbeat:Connect(function ()
		callback()
	end)

	return function ()
		connection:Disconnect()
	end
end

-- Connects a callback to every frame for as long as the place runs, as a transport takes it
local function heartbeat(callback: () -> ())
	connect(callback)
end

-- A child by name, made when it is missing, so a second server VM attaches to the same remotes
local function ensure(parent: Instance, name: string, class: string): Instance
	local existing: Instance? = parent:FindFirstChild(name)
	if existing then
		return existing
	end

	local child: Instance = Instance.new(class)
	child.Name = name
	child.Parent = parent

	return child
end

--[[
    The server's id for an instance a message names in one scope: the
    next one the scope's References folder counts, the folder made at the
    first, and then the same one for the instance's life. An ObjectValue
    named by the id holds it for the clients, and goes when it does
--]]

local function referencer(folder: Instance): (instance: Instance) -> number
	local ids: { [Instance]: number } = {}

	return function (instance: Instance): number
		local id: number? = ids[instance]
		if id then
			return id
		end

		local holder: Instance = ensure(folder, REFERENCES, "Folder")
		local given: number = holder:GetAttribute(COUNTER) :: number? or 1
		local value: ObjectValue = Instance.new("ObjectValue")

		holder:SetAttribute(COUNTER, given + 1)
		value.Name = tostring(given)
		value.Value = instance
		value.Parent = holder
		ids[instance] = given

		-- Fires once, and the instance's destruction disconnects it either way
		instance.Destroying:Once(function ()
			ids[instance] = nil
			value:Destroy()
		end)

		return given
	end
end

-- The client's instance for an id: its ObjectValue's, which is nil until the instance streams in
local function resolver(folder: Instance): (id: number) -> Instance?
	return function (id: number): Instance?
		local holder: Instance? = folder:FindFirstChild(REFERENCES)
		local value = holder and holder:FindFirstChild(tostring(id)) :: ObjectValue?

		return value and value.Value
	end
end

--[[
    Calls back on the client with an id each time its ObjectValue holds
    an instance: when it arrives with one, and when its Value is set to
    one as the instance streams in. The folder is the server's to make,
    so it is watched for until it exists. Each connection lives as long
    as the place, or as the ObjectValue it watches
--]]

local function arrivals(folder: Instance): (callback: (id: number) -> ()) -> ()
	return function (callback: (id: number) -> ())
		local function watch(child: Instance)
			local id: number? = tonumber(child.Name)
			if not id or not child:IsA("ObjectValue") then
				return
			end

			local value = child :: ObjectValue
			local function arrived()
				if value.Value then
					callback(id :: number)
				end
			end

			arrived()
			value:GetPropertyChangedSignal("Value"):Connect(arrived)
		end

		local function open(holder: Instance)
			holder.ChildAdded:Connect(watch)

			for _, child: Instance in holder:GetChildren() do
				watch(child)
			end
		end

		local holder: Instance? = folder:FindFirstChild(REFERENCES)

		if holder then
			open(holder)
		else
			folder.ChildAdded:Connect(function (child: Instance)
				if child.Name == REFERENCES then
					open(child)
				end
			end)
		end
	end
end

-- A child by name, waited for and warned about until it exists, since the server may not have made it yet
local function await(parent: Instance, name: string): Instance
	local child: Instance? = parent:WaitForChild(name, WAIT_SECONDS)
	while not child do
		warn(`Volt: still waiting for {parent:GetFullName()}.{name}`)
		child = parent:WaitForChild(name, WAIT_SECONDS)
	end

	return child :: Instance
end

--[[
    Opens the transport for one scope on one side. The services are
    fetched here rather than at load because the package is required
    under Lune, where there is no DataModel. Every connection made here
    lives as long as the place: a generated module is required once and
    never released. Outside a running game, as in a story tool, the
    transport drops every packet and hears none, so the generated API
    keeps its shape and does nothing
--]]

function Remotes.open(scope: string, server: boolean): Transport
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local spawn: Spawn = task.spawn

	-- The Heartbeat still runs, so what a fire wrote is dropped every frame rather than kept
	if not RunService:IsRunning() then
		return {
			inert = true,
			reliable = nothing,
			unreliable = nothing,
			receive = nothing,
			heartbeat = heartbeat,
			spawn = spawn,
			players = nobody,
			playerAdded = nothing,
			playerRemoving = nothing,
			now = never,
			reference = never,
			resolve = absent,
			resolved = nothing,
		}
	end

	local folder: Instance
	local reliable: RemoteEvent
	local unreliable: UnreliableRemoteEvent

	if server then
		folder = ensure(ensure(ReplicatedStorage, FOLDER, "Folder"), scope, "Folder")
		reliable = ensure(folder, RELIABLE, "RemoteEvent") :: RemoteEvent
		unreliable = ensure(folder, UNRELIABLE, "UnreliableRemoteEvent") :: UnreliableRemoteEvent
	else
		folder = await(await(ReplicatedStorage, FOLDER), scope)
		reliable = await(folder, RELIABLE) :: RemoteEvent
		unreliable = await(folder, UNRELIABLE) :: UnreliableRemoteEvent
	end

	-- Every scope's server transport is served through the VM's one hub, which is what lets a bot reach it
	if server then
		return Remotes.hub():serve(scope, {
			reliable = function (player: any, packet: buffer, side: { any }?)
				reliable:FireClient(player, packet, side)
			end,

			unreliable = function (player: any, packet: buffer, side: { any }?)
				unreliable:FireClient(player, packet, side)
			end,

			receive = function (handler: Handler)
				reliable.OnServerEvent:Connect(handler)
				unreliable.OnServerEvent:Connect(handler)
			end,

			heartbeat = heartbeat,
			spawn = spawn,

			players = function (): { any }
				return Players:GetPlayers()
			end,

			playerAdded = function (callback: (player: any) -> ())
				Players.PlayerAdded:Connect(callback)
			end,

			playerRemoving = function (callback: (player: any) -> ())
				Players.PlayerRemoving:Connect(callback)
			end,

			-- A player is parented to Players until the engine has let them go
			present = function (player: any): boolean
				return player.Parent ~= nil
			end,

			now = now,
			reference = referencer(folder),
		})
	end

	return {
		reliable = function (_, packet: buffer, side: { any }?)
			reliable:FireServer(packet, side)
		end,

		unreliable = function (_, packet: buffer, side: { any }?)
			unreliable:FireServer(packet, side)
		end,

		receive = function (handler: Handler)
			-- The client hears from the server alone, so the handler's player is nil
			local function receive(packet: buffer, side: { any }?)
				handler(nil, packet, side)
			end

			reliable.OnClientEvent:Connect(receive)
			unreliable.OnClientEvent:Connect(receive)
		end,

		heartbeat = heartbeat,
		spawn = spawn,
		resolve = resolver(folder),
		resolved = arrivals(folder),
	}
end

--[[
    The VM's hub, which every server transport is served through and
    every bot is made by, made the first time either asks for it. Only a
    server in a running game has one, so no client can make a bot
--]]

function Remotes.hub(): Hub
	local RunService = game:GetService("RunService")

	assert(RunService:IsServer() and RunService:IsRunning(), "Volt: bots belong to the server of a running game")

	if not Shared then
		Shared = Hub.new(task.spawn, connect)
	end

	return Shared :: Hub
end

return Remotes
