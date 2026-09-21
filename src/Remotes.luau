--[[
    The real transport: the remotes under ReplicatedStorage.Volt.<scope>,
    found or created by the server and awaited by the client, the
    Heartbeat, the player list with its join and leave signals, and the
    scheduler; the one file in the runtime that touches the DataModel.
    Outside a running game it is a transport that drops every packet
--]]

--!strict
local Config = require("./Config/Runtime")
local Types = require("./Config/Types/Runtime")

type Handler = Types.Handler
type Spawn = Types.Spawn
type Transport = Types.Transport

local FOLDER: string = Config.folder
local RELIABLE: string = Config.reliable
local UNRELIABLE: string = Config.unreliable
local WAIT_SECONDS: number = Config.waitSeconds

local Remotes = {}

-- What every fire, connection and signal of the transport does outside a running game
local function nothing() end

local function nobody(): { any }
	return {}
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

	local function heartbeat(callback: () -> ())
		RunService.Heartbeat:Connect(callback)
	end

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

	if server then
		return {
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
		}
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
	}
end

return Remotes
