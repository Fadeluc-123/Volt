--[[
    Proves a send grows its buffer and keeps what was written, flushes
    exactly the bytes and slots written and nothing else, splits an
    unreliable packet between messages to fit the budget with none
    straddling, and copies a broadcast into every target it should reach
--]]

--!strict
local Suite = require("./Suite")
local Send = require("@volt/Send")

local describe = Suite.describe
local test = Suite.test
local expect = Suite.expect

type Send = Send.Send
type State = Send.State

type Fired = { target: any, packet: buffer, side: { any }? }

-- A send that records what it fires
local function recorded(budget: number?): (Send, { Fired })
	local fired: { Fired } = {}
	local send: Send = Send.new(function (target: any, packet: buffer, side: { any }?)
		table.insert(fired, { target = target, packet = packet, side = side })
	end, budget)

	return send, fired
end

-- Writes one message of a count of bytes all holding a value, with a slot when given, and marks it
local function message(send: Send, count: number, value: number, slot: any?)
	local offset: number, out: buffer = send.allocate(count)

	buffer.fill(out, offset, value, count)

	if slot ~= nil then
		send.slot(slot)
	end

	send.mark()
end

-- The lengths of every packet fired, in firing order
local function lengths(fired: { Fired }): { number }
	local list: { number } = {}
	for _, entry: Fired in fired do
		table.insert(list, buffer.len(entry.packet))
	end
	return list
end

describe("Send", function ()
	test("grows the buffer past its first size and keeps every byte written", function ()
		local send: Send, fired: { Fired } = recorded()
		local state: State = send:add("a")

		send.current = state
		message(send, 50, 1)
		message(send, 50, 2)
		message(send, 50, 3)

		expect(buffer.len(state.out) >= 150).is(true)
		send:flush()

		expect(#fired).is(1)
		expect(buffer.len(fired[1].packet)).is(150)
		expect(buffer.readu8(fired[1].packet, 0)).is(1)
		expect(buffer.readu8(fired[1].packet, 99)).is(2)
		expect(buffer.readu8(fired[1].packet, 149)).is(3)
	end)

	test("flushes exactly what was written with its slots, then starts the state over", function ()
		local send: Send, fired: { Fired } = recorded()
		local state: State = send:add("a")

		send.current = state
		message(send, 5, 9, "first")
		send.slot("second")
		send:flush()

		expect(#fired).is(1)
		expect(fired[1].target).is("a")
		expect(buffer.len(fired[1].packet)).is(5)
		expect(table.concat(fired[1].side :: any, ",")).is("first,second")
		expect(state.cursor).is(0)
		expect(state.sideCursor).is(1)
		expect((next(state.side))).is(nil)

		send:flush()
		expect(#fired).is(1)
	end)

	test("fires no side array when nothing took a slot", function ()
		local send: Send, fired: { Fired } = recorded()

		send.current = send:add("a")
		message(send, 3, 0)
		send:flush()

		expect(fired[1].side).is(nil)
	end)

	test("splits an unreliable flush between messages to fit the budget, each slot with its message", function ()
		local send: Send, fired: { Fired } = recorded(10)

		send.current = send:add("a")
		message(send, 4, 1, "one")
		message(send, 4, 2)
		message(send, 4, 3, "three")
		send:flush()

		expect(table.concat(lengths(fired), ",")).is("8,4")
		expect(table.concat(fired[1].side :: any, ",")).is("one")
		expect(table.concat(fired[2].side :: any, ",")).is("three")
	end)

	test("never lets a message straddle two fires", function ()
		local send: Send, fired: { Fired } = recorded(10)

		send.current = send:add("a")
		message(send, 6, 1)
		message(send, 6, 2)
		message(send, 6, 3)
		send:flush()

		expect(table.concat(lengths(fired), ",")).is("6,6,6")
		expect(buffer.readu8(fired[3].packet, 0)).is(3)
	end)

	test("copies a broadcast into every target, all but one, a list or a set, and skips one who left", function ()
		local send: Send, fired: { Fired } = recorded(10)
		local a: State, b: State, c: State = send:add("a"), send:add("b"), send:add("c")

		send.current = send.scratch
		message(send, 3, 7, "slot")
		send:broadcast()

		expect(`{a.cursor},{b.cursor},{c.cursor}`).is("3,3,3")
		expect(`{a.side[1]},{a.marks[1]},{a.sideMarks[1]}`).is("slot,3,2")
		expect(send.scratch.cursor).is(0)

		message(send, 3, 8)
		send:broadcast(nil, "b")
		expect(`{a.cursor},{b.cursor},{c.cursor}`).is("6,3,6")

		message(send, 3, 9)
		send:broadcast({ "a", "ghost" })
		expect(`{a.cursor},{b.cursor},{c.cursor}`).is("9,3,6")

		message(send, 3, 10)
		send:broadcast({ c = true })
		expect(`{a.cursor},{b.cursor},{c.cursor}`).is("9,3,9")

		send:flush()

		local sizes: { number } = lengths(fired)
		table.sort(sizes)
		expect(table.concat(sizes, ",")).is("3,9,9")
	end)

	test("sends nothing more to a target that was removed", function ()
		local send: Send, fired: { Fired } = recorded()

		send.current = send:add("a")
		message(send, 3, 0)
		send:remove("a")
		send:flush()

		expect(#fired).is(0)
	end)
end)
