--[[
    The waits for instances a server's messages name, merged onto the
    runtime: on the client, a message naming one that has not arrived is
    kept as a copy of its own bytes and slots, read again by its own
    reader once the instance arrives, and dropped past its deadline
--]]

--!strict
local Awaited = {}

local Types = require("./Config/Types/Runtime")

type Message = Types.Message
type Runtime = Types.Runtime
type Waiter = Types.Waiter

-- Takes a value out of a list and says whether it was there
local function take(list: { any }, value: any): boolean
	local index: number? = table.find(list, value)
	if index then
		table.remove(list, index)
	end

	return index ~= nil
end

--[[
    Hears from the transport each id whose instance arrives, but only in
    a runtime that hears an event carrying an awaited instance, whose row
    alone has a timeout, so a schema with none touches no folder
--]]

function Awaited.arrivals(
	self: Runtime,
	messages: { [number]: Message },
	resolved: ((callback: (id: number) -> ()) -> ())?
)
	if not resolved then
		return
	end

	for _, message: Message in messages do
		if message.kind == "event" and message.timeout then
			resolved(function (id: number)
				self:_arrive(id)
			end)

			return
		end
	end
end

--[[
    The tail of every reader of an event that reaches an awaited instance:
    delivers the message when its reader found every instance it names,
    and otherwise keeps its bytes from start to cursor and its slots from
    sideStart to sideCursor, with the ids it waits on and its deadline,
    until they arrive. Returns the cursors, so a reader's tail is this one call
--]]

function Awaited.await(
	self: Runtime,
	id: number,
	packet: buffer,
	start: number,
	cursor: number,
	side: { any },
	sideStart: number,
	sideCursor: number,
	...: any
): (number, number)
	local missing: { number } = self._missing
	if missing[1] == nil then
		return self:deliver(id, nil, cursor, sideCursor, ...)
	end

	local bytes: number = cursor - start
	local copy: buffer = buffer.create(bytes)
	local replaying: Waiter? = self._replaying -- A message read again that must wait again keeps its first deadline

	buffer.copy(copy, 0, packet, start, bytes)
	self._missing = {}

	local waiter: Waiter = {
		id = id,
		packet = copy,
		side = table.move(side, sideStart, sideCursor - 1, 1, {}),
		deadline = replaying and replaying.deadline or os.clock() + self._messages[id].timeout :: number,
		ids = missing,
		stamp = self._stamp,
	}

	table.insert(self._waiters, waiter)

	for _, waited: number in missing do
		local list: { Waiter }? = self._awaited[waited]

		if list then
			table.insert(list, waiter)
		else
			self._awaited[waited] = { waiter }
		end
	end

	return cursor, sideCursor
end

--[[
    The instance an id names, which a client reader asks for: nil while
    it has not arrived, and while an earlier message waits on it, so
    those naming one instance keep their order. Either way the message
    being read then waits on the id. One read again has had its turn
--]]

function Awaited._lookup(self: Runtime, id: number): Instance?
	local resolve: ((id: number) -> Instance?)? = self._resolve
	local instance: Instance? = nil

	if resolve and (self._replaying or not self._awaited[id]) then
		instance = resolve(id)
	end

	if instance == nil and not table.find(self._missing, id) then
		table.insert(self._missing, id)
	end

	return instance
end

--[[
    An instance has arrived: every message waiting on its id stops
    waiting on it, and each that then waits on nothing is read again,
    in the order they were read
--]]

function Awaited._arrive(self: Runtime, id: number)
	local list: { Waiter }? = self._awaited[id]
	if not list then
		return
	end

	self._awaited[id] = nil

	for _, waiter: Waiter in list do
		take(waiter.ids, id)

		-- One a deadline took out, from a listener's flush while an earlier one was read again, is gone already
		if waiter.ids[1] == nil and take(self._waiters, waiter) then
			self:_replay(waiter)
		end
	end
end

--[[
    Reads a waiting message again from its copy, under the stamp of the
    packet it came in, so it reaches its hooks, queue and listeners as
    one from a packet does. An error is a decode failure named for it
--]]

function Awaited._replay(self: Runtime, waiter: Waiter)
	local message: Message = self._messages[waiter.id]
	local packet: buffer = waiter.packet

	self._stamp = waiter.stamp
	self._replaying = waiter

	local ok: boolean, problem: any = pcall(message.read, nil, packet, 0, waiter.side, 1, buffer.len(packet))

	self._replaying = nil
	self._stamp = self._newest

	if not ok then
		self:_undecoded(nil, waiter.id, problem)
	end
end

--[[
    Drops every waiting message past its deadline, at each flush: each
    is taken out of both tables, and only once that walk is done is each
    reported as a resolve failure naming the ids it still waited on
--]]

function Awaited._expire(self: Runtime)
	local waiters: { Waiter } = self._waiters
	if waiters[1] == nil then
		return
	end

	local now: number = os.clock()
	local expired: { Waiter } = {}

	for _, waiter: Waiter in waiters do
		if now >= waiter.deadline then
			table.insert(expired, waiter)
		end
	end

	for _, waiter: Waiter in expired do
		take(waiters, waiter)

		for _, id: number in waiter.ids do
			local list: { Waiter }? = self._awaited[id]

			if list and take(list, waiter) and list[1] == nil then
				self._awaited[id] = nil
			end
		end
	end

	for _, waiter: Waiter in expired do
		local message: Message = self._messages[waiter.id]
		local noun: string = #waiter.ids == 1 and "instance" or "instances"
		local unit: string = message.timeout == 1 and "second" or "seconds"
		local ids: string = table.concat(waiter.ids, ", ")

		self:fail(nil, "resolve", `{noun} {ids} did not arrive within {message.timeout} {unit}`, message.name)
	end
end

return Awaited
