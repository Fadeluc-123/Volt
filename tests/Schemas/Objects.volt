option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

event Objects {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: Instance, b: Instance(BasePart), c: Instance?, d: StreamedInstance(Model), e: unknown, f: unknown?),
}

event Items {
	from: Client, type: Reliable, call: SingleSync,
	data: (a: Enum.Material, b: EnumItem),
}
