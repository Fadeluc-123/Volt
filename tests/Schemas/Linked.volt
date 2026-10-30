option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

@depth(4) struct Linked<T> { value: T, next: Linked<T>? }

event Chain { from: Client, type: Reliable, call: SingleSync, data: Linked<u8> }
