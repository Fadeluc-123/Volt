--[[
    Proves the mock transport: a joined player reaches the server's list
    and signals and gets a client side of their own, a packet is copied
    when fired and delivered on the next step to the side it names, one
    for a player who left is dropped, and every Heartbeat fires once per
    step
--]]

--!strict
local task = require("@lune/task")

local Suite = require("./Suite")
local Volt = require("@volt")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Received = { player: any, packet: buffer, side: { any }? }

describe("Mock", function ()
	test("lists a joined player, tells the server, and hands back their client side", function ()
		local mock = Volt.mock(task.spawn)
		local joined: { string } = {}

		assert(mock.server.playerAdded, "the server side has players")(function (player: any)
			table.insert(joined, player.Name)
		end)

		local alice, client = mock:join("Alice")

		expect(alice.Name).is("Alice")
		expect(alice.UserId).is(1)
		expect(#assert(mock.server.players, "the server side has players")()).is(1)
		expect(table.concat(joined, ",")).is("Alice")
		expect(client.reliable).is_a("function")
	end)

	test("copies a packet and its side array when fired and delivers them on the next step", function ()
		local mock = Volt.mock(task.spawn)
		local alice, client = mock:join("Alice")
		local received: { Received } = {}
		local packet: buffer = buffer.create(2)
		local side: { any } = { "kept" }

		mock.server.receive(function (player: any, from: buffer, slots: { any }?)
			table.insert(received, { player = player, packet = from, side = slots })
		end)

		buffer.writeu8(packet, 0, 7)
		client.reliable(nil, packet, side)

		buffer.writeu8(packet, 0, 9)
		side[1] = "changed"
		expect(#received).is(0)

		mock:step()

		expect(#received).is(1)
		expect(received[1].player).is(alice)
		expect(buffer.readu8(received[1].packet, 0)).is(7)
		expect((received[1].side :: any)[1]).is("kept")
	end)

	test("delivers a server packet to the client it names and drops one for a player who left", function ()
		local mock = Volt.mock(task.spawn)
		local alice, aliceSide = mock:join("Alice")
		local bob, bobSide = mock:join("Bob")
		local counts: { [string]: number } = { Alice = 0, Bob = 0 }

		aliceSide.receive(function ()
			counts.Alice += 1
		end)
		bobSide.receive(function ()
			counts.Bob += 1
		end)

		mock.server.unreliable(alice, buffer.create(1))
		mock.server.reliable(bob, buffer.create(1))
		mock:leave(bob)
		mock:step()

		expect(counts.Alice).is(1)
		expect(counts.Bob).is(0)
	end)

	test("tells the server a player is leaving while they are still listed, then forgets them", function ()
		local mock = Volt.mock(task.spawn)
		local alice = mock:join("Alice")
		local listed: number = -1

		local players = assert(mock.server.players, "the server side has players")

		assert(mock.server.playerRemoving, "the server side has players")(function ()
			listed = #players()
		end)

		mock:leave(alice)

		expect(listed).is(1)
		expect(#players()).is(0)
	end)

	test("fires every Heartbeat once per step", function ()
		local mock = Volt.mock(task.spawn)
		local _, client = mock:join("Alice")
		local beats: number = 0

		mock.server.heartbeat(function ()
			beats += 1
		end)
		client.heartbeat(function ()
			beats += 1
		end)

		mock:step()
		mock:step()

		expect(beats).is(4)
	end)
end)
