option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

struct Pair<A, B> { first: A, second: B }
type Maybe<T> = T?
@private struct Box<T> { value: T, spare: T[0..2] }
export type Scores = Pair<u16, u16>

event Moves { from: Client, type: Reliable, call: SingleSync, data: (a: Pair<u8, u8>, b: Maybe<Pair<u8, u8>>, c: Pair<u16, string(0..4)>) }
event Boxes { from: Client, type: Reliable, call: SingleSync, data: (a: Box<u8>, b: Scores) }
