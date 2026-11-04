# Changelog

Every notable change to Volt is recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

0.1.0 is Volt's first release, so its entry lists everything a game gets. The README explains each item under the same name.

## [0.1.0] - 2026-11-04

### Added

#### The schema language

- The schema: one `.volt` file, or a folder of them, that lists every message a game sends between the server and its players, with options at the top, `--` comments and namespaces that group messages and types.
- Events, one-way messages a client, the server or both sides fire (`from: Client`, `Server` or `Both`).
- Functions, a question with an answer: a player calls the server, or with `from: Server` the server calls one player, and every call has a `timeout`.
- Parameter packs, such as `data: (x: f32, y: f32)`, which a listener receives as separate arguments.
- Whole numbers `u8` to `u64` and `i8` to `i64`, decimals `f16`, `f32` and `f64`, and `q8(min..max)` and `q16(min..max)`, each narrowed by a range.
- `boolean`, `string`, `string.utf8` for text that must be valid UTF-8, `buffer` and `unknown`.
- Literal types, such as `"melee"`, `2` or `true`, which send nothing.
- The Roblox types `Vector3`, `Vector2`, `CFrame`, `AlignedCFrame`, `QuaternionCFrame`, `UDim2`, `NumberRange`, `Rect`, `Ray`, `Region3`, `Color3`, `BrickColor`, `DateTime`, `DateTimeMillis`, `Enum.` items and `EnumItem`, with type arguments that pick how each number is sent.
- `Instance`, `StreamedInstance` and `AwaitedInstance`, which makes a player's client hold the message until the instance has streamed in.
- Optionals, arrays, maps, sets, structs, enums, tagged enums and unions.
- Named types (`type`, `struct` and `enum`), and `@private` to keep a type's Luau type out of your scripts.
- Spreads, `..Name`, which copy one struct's fields into another.
- Generic types, such as `struct Pair<A, B>`.
- Recursive types, with `@depth(n)` setting the deepest level a value may sit at.

#### Events and functions

- `Reliable`, `Unreliable` and `OrderedUnreliable` events, the last dropping a message older than the last one heard.
- Channels, `channel Name`, each a second line of reliable messages in its own order.
- The five listener modes, `SingleSync`, `ManySync`, `SingleAsync`, `ManyAsync` and `Polling`, whose messages your code reads with `iter`.
- The generated `Network` modules: `fire`, `fireAll`, `fireList`, `fireSet` and `fireExcept` on the server, `fire` on the client, and `on`, which returns a function that disconnects the listener.
- `invoke`, which returns `true` and the answer or `false` and the reason it failed, or a Promise with `yield = promise`, and `connected()` for a function the server calls.
- Sending once a frame: every message fired in a frame goes out together at the next Heartbeat, and `flush`, `flushBytes` and `manualReplication` with `Network.flush()` change when.
- A client in a running game sends at most 60 times a second whatever its frame rate, so a player at 240 FPS sends no more packets than one at 60.
- Reliable messages fired at a player before their handshake are held and sent right after it.
- `@delta` events, which send each player only the fields that changed since the last value they were sent.
- `@dictionary` string types, which send each string to each player once and then as a 2-byte id.
- `option stamp`, with `Network.serverTime()` on the client reading when the server sent a message.
- `Network.budget(bytesPerSecond)` on the server, capping what one schema sends a player.
- The player callbacks `onJoin`, `onHandshake` and `onLeave`, and `Network.traffic(player)`.
- `Network.events`, `Network.functions` and `Network.exports`, which look up messages by name, and a handle type for each kind of entry, such as `ServerEvent<A...>`.
- `Network.version`, the version of the `volt` that compiled the module.

#### Safety defaults

- Every value the server receives is checked against the schema, after the packet's own checks for its type, its size (`maxPacket`) and the player's packet rate (`maxPacketsPerSecond`), and these checks cannot be turned off.
- The sending side checks your values before writing them, unless `option writeValidation = false`.
- Rate limits of 120 messages a second per event and 60 calls a second per function for each player, changed with `rate`, `functionRate` or `Network.rate` while the game runs.
- The schema-mismatch kick: a client whose module came from another schema is kicked with both schema hashes.
- `maxOutgoing`, the most one player's outgoing data may hold in one frame.
- Eleven failure kinds, `packet`, `rate`, `handshake`, `decode`, `resolve`, `listener`, `handler`, `outgoing`, `queue`, `departed` and `budget`, each counted, and each message-scoped failure's detail starting with the message's name.
- `Network.onFailure(handler)`, which returns the handler it replaced, and `Network.stats()` and `Network.stats(player)`.
- The version check at `require`, which refuses a module compiled by a `volt` whose first two numbers differ from the runtime's, naming the scope to update.
- A module required outside a running game, such as from the command bar, sends nothing and creates no remotes.

#### More tools

- Hooks, `Network.hooks.beforeSend` and `Network.hooks.afterReceive`, which can drop a message before it is sent or after it is received.
- Exported serializers: `export` in front of a type gives it a `write` and a `read`, such as for a DataStore.
- The mock transport, `Volt.mock(spawn)`, and `Volt.start(schema, transport)`, for testing your networking under Lune without Studio.
- Bots, `Volt.addBot`, `Volt.removeBot` and `Volt.connectBot`, stand-in players that exist only on the server, with `Network.isBot`.
- The packet inspector, `option inspectorOutput`, a module that reads a packet back into its messages for PacketProfiler.
- MicroProfiler labels, `option profileLabels`.
- Shards, which split a schema too big for one module, past 150 locals or `option shardSize` entries.
- Colors in VS Code: an extension in Volt's repository that colors `.volt` files.

#### The command line

- `volt <schema.volt | folder> [<file.volt> ...]`, which compiles one file, or every `.volt` file directly inside a folder, plus any further files, as one schema.
- `--check`, which writes nothing and fails when the modules on disk differ from what the schema compiles to.
- `--watch`, which compiles again each time the schema changes.
- `--ast`, which prints the schema with every default filled in, and `--quiet`, which leaves out the `ok` line.
- Errors and warnings with their file, line, column and code, and the schema hash on success.
- The options `clientOutput`, `serverOutput`, `typesOutput`, `inspectorOutput`, `runtime`, `scope`, `casing`, `writeValidation`, `manualReplication`, `flush`, `flushBytes`, `maxPacket`, `maxPacketsPerSecond`, `maxOutgoing`, `unreliableBudget`, `stamp`, `queue`, `rate`, `functionRate`, `timeout`, `yield`, `promise`, `shardSize` and `profileLabels`.

#### Install

- The `volt` compiler for Windows, Linux and macOS on x86-64, and Linux and macOS on ARM64, attached to the GitHub Release and installed with `rokit add fadeluc-123/volt`.
- The runtime on Wally as `fadeluc-123/volt`, installed with `Volt = "fadeluc-123/volt@0.1.0"`, with no dependencies.

[0.1.0]: https://github.com/Fadeluc-123/Volt/releases/tag/v0.1.0
