# Volt

Networking for Roblox games: one file describes every message, and a tool turns it into typed Luau modules.

## Contents

- [What Volt is](#what-volt-is)
- [Why use it](#why-use-it)
- [Install](#install)
- [Your first schema](#your-first-schema)
- [Compile](#compile)
- [Use it in your scripts](#use-it-in-your-scripts)
- [Types](#types)
- [Choosing how a message travels](#choosing-how-a-message-travels)
- [Safety defaults](#safety-defaults)
- [More tools](#more-tools)
- [Colors in VS Code](#colors-in-vs-code)
- [Options](#options)
- [Troubleshooting](#troubleshooting)
- [Versions](#versions)
- [Working on Volt](#working-on-volt)

## What Volt is

Volt is a networking library for Roblox. You describe every message your game sends between the server and its players in one text file, called a schema, and a command-line tool called `volt` turns that file into Luau modules. Your scripts call those modules instead of creating and firing RemoteEvents.

## Why use it

Your game sends less data. Volt writes each message into a buffer, which is a block of raw bytes, instead of sending Luau tables. A number from 0 to 255 takes one byte, and eight true or false values share one byte. The reliable messages fired during one frame go out together, in one remote call per player.

The code Volt writes reads and writes each value at a fixed place in the buffer, so turning a message into bytes and back takes little work.

The server checks every value. Before your code sees a message from a player, Volt checks each value against the type the schema gives it: its range, its length, its class. A message that fails is dropped and reported. Every message from a player also has a rate limit, so one player cannot flood the server.

Every message is listed in one place. The schema names each message, who sends it and what it carries, so all of your game's network traffic can be read in one file. The generated modules are fully typed, so your editor knows the type of every argument.

## Install

Volt has two parts. The first is `volt`, a compiler: a program that reads one kind of file and writes code from it. It runs on your computer while you work. The second is the runtime, a small Luau package that runs inside your game and does the sending and receiving. Rokit installs the compiler and Wally installs the runtime.

These steps assume your game is a Rojo project that already uses Rokit, which installs command-line tools, and Wally, which installs Luau packages.

1. Install the compiler. In your game's folder, run:

   ```sh
   rokit add fadeluc-123/volt
   ```

   This pins `volt` in your `rokit.toml`, so everyone who works on the game gets the same version.

2. Add the runtime to your `wally.toml`, under `[dependencies]`. Wally 0.3.2 has no `add` command, so you type the line yourself:

   ```toml
   [dependencies]
   Volt = "fadeluc-123/volt@0.1.0"
   ```

   Then install it:

   ```sh
   wally install
   ```

   Keep the name on the left as `Volt`, with a capital V. Wally names the entry in `Packages/` after it, Roblox instance names are case sensitive, and every generated module requires `ReplicatedStorage.Packages.Volt` unless told otherwise, so a lowercase name fails at the first `require`. A different name works only if every schema sets a matching `option runtime`, and that only helps your game's own schemas. A package built on Volt that runs its own scope was compiled with `ReplicatedStorage.Packages.Volt` written into it, so a game that uses any such package installs Volt as `Volt`.

   If your game uses a package that was compiled with `option yield = promise`, also install evaera's Promise library as `Promise`:

   ```toml
   Promise = "evaera/promise@4.0.0"
   ```

   That puts it at `ReplicatedStorage.Packages.Promise`, the path the package's client module requires. The package's own copy of Promise sits inside `Packages/_Index`, which that path never reaches.

3. Map Wally's `Packages` folder to `ReplicatedStorage.Packages` in your Rojo project file. The examples in this README also put `src/Shared` at `ReplicatedStorage.Shared`, the server scripts in `ServerScriptService` and the client scripts in `StarterPlayerScripts`. A `default.project.json` that does all of that:

   ```json
   {
   	"name": "MyGame",
   	"tree": {
   		"$className": "DataModel",
   		"ReplicatedStorage": {
   			"Packages": { "$path": "Packages" },
   			"Shared": { "$path": "src/Shared" }
   		},
   		"ServerScriptService": {
   			"Server": { "$path": "src/Server" }
   		},
   		"StarterPlayer": {
   			"StarterPlayerScripts": {
   				"Client": { "$path": "src/Client" }
   			}
   		}
   	}
   }
   ```

4. Give the type checker Volt's types. Run these two commands after every `wally install`:

   ```sh
   rojo sourcemap default.project.json --output sourcemap.json
   wally-package-types --sourcemap sourcemap.json Packages/
   ```

   For each package, Wally writes a small file in `Packages/` that points at the package's real code, and those files leave the package's types out. The generated modules use Volt's types, such as `Volt.Runtime`, so in a game that uses `--!strict` the type checker reports `Unknown type 'Volt.Runtime'` and dozens of errors after it until this step runs. The first command writes a map of your project to `sourcemap.json`. The second uses that map to rewrite the small files with the types included. If you do not have `wally-package-types` yet, add it with `rokit add JohnnyMorganz/wally-package-types`.

## Your first schema

A schema is a text file whose name ends in `.volt`. It lists your messages and says where `volt` writes the modules. Save this as `Game.volt` in the root folder of your game's project:

```
-- Every message this game sends between the server and its players
option clientOutput = "src/Shared/Network/Client.luau"
option serverOutput = "src/Shared/Network/Server.luau"
option typesOutput = "src/Shared/Network/Types.luau"

-- A player sends the server a small number
event Ping {
	from: Client,
	type: Reliable,
	call: SingleAsync,
	data: u8,
}

-- The server sends a small number back
event Pong {
	from: Server,
	type: Reliable,
	call: SingleAsync,
	data: u8,
}

-- A player asks the server a question and waits for the answer
function Echo {
	data: string(0..32),
	return: string(0..32),
}
```

Here is what each line does.

- A line that starts with `--` is a comment. Volt ignores it.
- `option clientOutput = "..."` is where `volt` writes the module your LocalScripts use. The path is relative to the folder that holds `Game.volt`.
- `option serverOutput = "..."` is where it writes the module your server Scripts use.
- `option typesOutput = "..."` is where it writes a module of types for code that both sides share. It is optional; leave the line out if you do not need it.
- `event Ping {` starts an event named `Ping`. An event is a one-way message: one side fires it, the other side listens, and nothing comes back.
- `from: Client` says who fires it: `Client` for a player's LocalScripts, `Server` for the server, or `Both`.
- `type: Reliable` means the message always arrives, exactly once, in the order it was fired. An `Unreliable` message can be lost. [Choosing how a message travels](#choosing-how-a-message-travels) says when to use each.
- `call: SingleAsync` says how the listening side runs its listener. `Single` allows one listener, and `Async` runs each message on its own thread, so the listener may wait. The same section explains the other modes.
- `data: u8` is what the message carries: one whole number from 0 to 255. `u8` is short for "unsigned 8-bit", a number that is never negative and fits in one byte. [Types](#types) lists every type.
- `}` ends the event. Each key inside it ends with a comma.
- `event Pong { ... }` is the same shape with `from: Server`, so the server fires it and the players listen.
- `function Echo {` starts a function. A function is a question with an answer: a player calls it, the server runs a handler, and the handler's return value goes back to that player. Functions always go from a client to the server.
- `data: string(0..32)` is what the player sends: a string from 0 to 32 bytes long.
- `return: string(0..32)` is what the server answers with.

The schema leaves two options at their defaults. `option runtime` is where the modules find the Volt runtime, and it defaults to `ReplicatedStorage.Packages.Volt`, where Wally put it. `option scope` names the folder Volt makes for this schema's remotes, and it defaults to the schema's file name, so this schema's remotes live in `ReplicatedStorage.Volt.Game`. Two schemas with different names never see each other's messages.

`data` can also be a list of named values, called a parameter pack. With `data: (x: f32, y: f32)` the sender calls `fire(x, y)` and the listener receives `x` and `y` as two arguments.

## Compile

`volt` does not create folders, so make the output folder once (in PowerShell, leave out `-p`):

```sh
mkdir -p src/Shared/Network
```

Then run the compiler on the schema:

```sh
volt Game.volt
```

It prints one line:

```
Game.volt: ok, schema hash 0x894D330D
```

The schema hash is a fingerprint of the schema. Any change to a message or an option changes it, so yours will differ once your schema does.

These files now exist:

| File | Required by |
|---|---|
| `src/Shared/Network/Client.luau` | your LocalScripts |
| `src/Shared/Network/Server.luau` | your server Scripts |
| `src/Shared/Network/Types.luau` | shared code that wants the types; written only when `typesOutput` is set |

Each one starts with a comment saying it was generated. Never edit them. Change the schema and run `volt` again instead.

Run `volt` again after every change to the schema. The client module and the server module must come from the same schema, or the server kicks every player (see [Safety defaults](#safety-defaults)).

When the schema has a mistake, `volt` prints each one with its line, its column and a code, writes nothing and exits with code 1:

```
Game.volt:5:2: error V2003: unknown key "form" in event Ping; keys are from, type, call, data, queue, rate
    5 | 	form: Client,
      | 	^^^^

Game.volt:4:7: error V2004: missing key "from" in event Ping
    4 | event Ping {
      |       ^^^^
```

The command takes three flags:

```
usage: volt <schema.volt | folder> [<file.volt> ...] [--check] [--ast] [--quiet]
```

- `--check` writes nothing. It compiles the schema and compares the result with the files already on disk, line endings aside.
- `--ast` also prints the schema in its full form, with every default filled in.
- `--quiet` leaves out the `ok` line.

Use `--check` in continuous integration (CI), the checks that run on every push, to prove the committed modules match the schema:

```sh
volt Game.volt --check
```

When they match, it prints the usual `ok` line and exits with code 0. When they do not, it names each file and exits with code 1:

```
Game.volt: src/Shared/Network/Client.luau is out of date
Game.volt: src/Shared/Network/Server.luau is out of date
```

Each module's first comment names the Volt version that wrote it, so after you upgrade `volt` every module reads as out of date until you compile again.

### A schema in several files

A large game can split its schema across a folder. `volt` compiles every `.volt` file directly inside the folder, and none in its subfolders, as one schema. This example has one mode, `Arena`, that reuses a file the main game keeps elsewhere:

```
Arena/
  Network/          the generated modules go here
  Schemas/
    Arena.volt      the options
    Round.volt
    Types.volt
Game/
  Schemas/
    Combat.volt
    Types.volt
```

One file in the folder sets the options. Here it is `Arena/Schemas/Arena.volt`, which may also hold declarations:

```
option clientOutput = "../Network/Client.luau"
option serverOutput = "../Network/Server.luau"
option typesOutput = "../Network/Types.luau"

namespace Arena {
	event Ready {
		from: Client, type: Reliable, call: SingleSync,
	}
}
```

The other files hold only declarations. `Arena/Schemas/Round.volt` uses a type that `Arena/Schemas/Types.volt` declares:

```
namespace Round {
	event Start {
		from: Server, type: Reliable, call: SingleAsync,
		data: (score: Score),
	}
}
```

```
type Score = u16(0..1000)
```

Create `Arena/Network` once, then compile the folder by naming it:

```sh
volt Arena/Schemas
```

The output paths are relative to the options file's folder, and the scope is the options file's name, `Arena`. To reuse a file kept in another folder, name it after the folder. Every path on the command line is relative to the folder you run the command in:

```sh
volt Arena/Schemas Game/Schemas/Combat.volt
```

A reused file compiles only when every name it uses is declared somewhere in the schema. This is how a mode builds on a base layer of shared types. `Game/Schemas/Combat.volt` uses `Hit`:

```
namespace Combat {
	event Strike {
		from: Client, type: Reliable, call: SingleSync,
		data: Hit,
	}
}
```

and the game declares `Hit` in `Game/Schemas/Types.volt`:

```
struct Hit { target: u16, amount: u16(1..999) }
```

So the command above fails, because nothing in the schema declares `Hit`:

```
Game/Schemas/Combat.volt:4:9: error V3001: unknown type "Hit"
    4 | 		data: Hit,
      | 		      ^^^
```

There are two fixes. The mode's own `Arena/Schemas/Types.volt` can declare `Hit`, or you can pass the game's `Types.volt` as one more file:

```sh
volt Arena/Schemas Game/Schemas/Types.volt Game/Schemas/Combat.volt
```

```
Arena/Schemas/Arena.volt: ok, schema hash 0x41DAE044
```

Do one or the other. A name declared in both is an error:

```
Game/Schemas/Types.volt:1:8: error V3002: "Hit" is declared twice
    1 | struct Hit { target: u16, amount: u16(1..999) }
      |        ^^^
```

There is no `import`. The files are read in a fixed order, the options file first, then the folder's other files by name, then the extra files in the order given, so every machine gets the same result. An option in any file but the options file is an error.

## Use it in your scripts

Every script requires its own side's module and names it `Network`. This server Script is `src/Server/Main.server.luau`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Shared.Network.Server)

-- Runs every time a player fires Ping
Network.Ping.on(function(player, value)
	print(`{player.Name} sent Ping {value}`)

	-- Answer the player who sent it
	Network.Pong.fire(player, value + 1)

	-- Tell every player in the server
	Network.Pong.fireAll(value)
end)

-- Runs every time a player invokes Echo; what it returns goes back to that player
Network.Echo.on(function(player, word)
	return string.upper(word)
end)
```

This LocalScript is `src/Client/Main.client.luau`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Shared.Network.Client)

-- Runs every time the server fires Pong at this player
local disconnect = Network.Pong.on(function(value)
	print(`Pong {value}`)
end)

-- Send Ping to the server
Network.Ping.fire(7)

-- Ask Echo a question and wait for the answer
local ok, answer = Network.Echo.invoke("hello")
if ok then
	print(`Echo answered {answer}`)
else
	warn(`Echo failed: {answer}`)
end

-- Stop listening to Pong
disconnect()
```

With one player named Alice, the server prints:

```
Alice sent Ping 7
```

and the client prints:

```
Pong 8
Pong 7
Echo answered HELLO
```

The client hears both Pongs before the Echo answer because the server fired them first. Reliable messages from one side arrive in the order they were fired, and a function's answer travels in that same line.

On the server:

- `Network.Ping.on(listener)` connects a listener to an event the clients fire. The listener receives the player, then the data. `on` returns a function that disconnects the listener.
- `Network.Pong.fire(player, value)` sends to one player.
- `Network.Pong.fireAll(value)` sends to every player.
- `Network.Pong.fireList({ alice, bob }, value)` sends to the players in a list, `Network.Pong.fireSet({ [alice] = true }, value)` to the players in a set, and `Network.Pong.fireExcept(alice, value)` to everyone but one player.
- `Network.Echo.on(handler)` connects the one handler a function has. Its return values are the answer. It runs on its own thread, so it may wait, for example on a DataStore, and the server never times it out.

On the client:

- `Network.Ping.fire(value)` sends to the server.
- `Network.Pong.on(listener)` connects a listener to an event the server fires. The listener receives the data. It also returns a function that disconnects it.
- `Network.Echo.invoke(...)` sends the question and waits. It returns `true` and the answer, or `false` and the reason it failed.

A call fails with one of these reasons:

- `timeout`: no answer came within the function's timeout, 10 seconds by default.
- `no handler`: the server has not connected a handler to the function.
- `rate limited`: the player called the function more often than its rate allows.
- `too many calls`: 65,535 calls to this function are already waiting.
- `edit mode`: the game is not running, for example when the module is required from the command bar or a UI story tool.
- `dropped`: the call did not fit in what the client may send in one frame (8,192 bytes by default, see `maxPacket` in [Options](#options)), so Volt dropped it before it left and reported an `outgoing` failure. The call fails at once, without waiting.
- Any other reason is the first line of the handler's error, without the script's position: a handler that runs `error("no echo today")` gives the reason `no echo today`.

A value the schema does not allow raises an error where you fire it. `Network.Ping.fire(300)` raises `Ping: expected u8`, since 300 does not fit in a `u8`, and nothing is sent.

Volt does not send a message the moment you fire it. It collects what you fire and sends it once per frame, on `RunService.Heartbeat`, so a message arrives about one frame later.

A message that arrives before any listener is connected waits in a queue, up to 64 messages per event. The first listener you connect receives them in the order they arrived.

An event with `Single` in its `call` allows one listener at a time. Disconnect the first before you connect another.

Requiring a module outside a running game does no harm. `fire` and `on` work but nothing is sent, `invoke` fails with `edit mode`, and no remotes are created. Requiring the server module never waits. The client module waits until the server has created the remotes.

### Reading messages when you choose

With `call: Polling`, an event has no listener. Its messages wait in a queue until your code reads them with `iter`. Add this event to `Game.volt` and run `volt Game.volt` again:

```
-- A player votes for a map; the server reads the votes when it is ready
event Vote {
	from: Client,
	type: Reliable,
	call: Polling,
	data: u8,
}
```

On the server, read the votes once a frame:

```lua
local RunService = game:GetService("RunService")

-- Once a frame, read every vote that arrived since the last frame
RunService.Heartbeat:Connect(function()
	for _, player, map in Network.Vote.iter() do
		print(`{player.Name} voted for map {map}`)
	end
end)
```

On the client, fire it like any event:

```lua
-- Vote for map 2
Network.Vote.fire(2)
```

The server prints `Alice voted for map 2`. Each step of the loop gives a running count, the player and the data, and removes that message from the queue. On the client the loop gives the count and the data, with no player. The queue holds 64 messages by default, and when it is full the oldest is dropped.

## Types

Every value in `data` and `return` has a type. The type decides which values are allowed and how many bytes they take.

A range in parentheses narrows a type. Both ends are included: `u8(0..8)` allows 0 through 8. `(10..)` and `(..10)` leave one end open. For a string, a buffer or an array, the range is the length, and one number means an exact length.

| Type | What it holds | Bytes | Example |
|---|---|---|---|
| `u8`, `u16`, `u24`, `u32`, `u48`, `u64` | Whole numbers from 0 up. `u8` holds up to 255, `u16` up to 65,535, `u32` up to 4,294,967,295. `u64` stops at 2^53, the largest whole number a Luau number holds exactly. | 1, 2, 3, 4, 6, 8 | `u8(0..8)` |
| `i8`, `i16`, `i24`, `i32`, `i48`, `i64` | Whole numbers that can be negative. `i8` holds -128 to 127. | 1, 2, 3, 4, 6, 8 | `i16(-100..100)` |
| `f16`, `f32`, `f64` | Numbers with decimals. `f16` is the least precise and `f64` is a full Luau number. NaN is never allowed. | 2, 4, 8 | `f32(0..1)` |
| `q8(min..max)`, `q16(min..max)` | A decimal between `min` and `max`, rounded to one of 256 or 65,536 evenly spaced steps. The range is required. | 1, 2 | `q16(-3.2..3.2)` |
| `boolean` | `true` or `false`. | 1 bit; eight share a byte | `boolean` |
| `string` | A string, measured in bytes. | the bytes, plus 1 or 2 for the length | `string(0..64)`, `string(8)` |
| `string.utf8` | Text that must be valid UTF-8. The range still counts bytes, not characters, so `string.utf8(1..4)` holds `"日"` (3 bytes) but not `"日本"` (6). The receiver refuses invalid text on every read. | the bytes, plus 1 or 2 for the length | `string.utf8(1..4096)` |
| `buffer` | A Luau buffer. | the bytes, plus 1 or 2 for the length | `buffer(0..1024)` |
| `unknown` | Any Luau value. It travels beside the buffer and Volt never checks it. | 1 bit | `unknown` |
| `"melee"`, `2`, `true` | Exactly that one value, called a literal type. The receiver already knows it, so nothing is sent; the sender refuses any other value while `writeValidation` is on, as it is by default. | none | `struct { kind: "melee", damage: u16 }` |
| `Vector3`, `Vector3<T>` | A Vector3, each part sent as `T`, which is `f32` unless you give one. | 12 by default | `Vector3<q16(-1024..1024)>` (6 bytes) |
| `Vector2`, `Vector2<T>` | A Vector2. | 8 by default | `Vector2<i16>` |
| `CFrame`, `CFrame<P, R>` | A CFrame: the position as three `P`, the rotation as three `R`, both `f32` by default. | 24 by default | `CFrame<f32, q16(-3.2..3.2)>` |
| `AlignedCFrame`, `AlignedCFrame<P>` | A CFrame turned to one of the 24 rotations that line up with the axes, plus a position. | 13 by default | `AlignedCFrame` |
| `Color3` | A color, 0 to 255 per channel. | 3 | `Color3` |
| `BrickColor` | A BrickColor. | 2 | `BrickColor` |
| `DateTime`, `DateTimeMillis` | A DateTime, to the second or to the millisecond. | 8 | `DateTimeMillis` |
| `Instance`, `Instance(Class)` | An instance the receiver can see, of the class if you name one. | none; it travels beside the buffer | `Instance(BasePart)` |
| `StreamedInstance(Class)` | An instance the receiver may not have streamed in yet. It arrives as `nil` when it has not. | none; it travels beside the buffer | `StreamedInstance(Model)` |
| `Enum.Material` and every other `Enum.` name | An item of that one Roblox enum. | 2 | `Enum.KeyCode` |
| `EnumItem` | An item of any Roblox enum. The enum's name travels with it. | 4 or more | `EnumItem` |

A string, buffer or array with a range stores its length in the smallest number that holds the range, and one with an exact length stores none. With no range, the length takes 2 bytes and the most allowed is 65,535.

Types can be combined:

| Form | What it holds | Example |
|---|---|---|
| `T?` | A `T`, or `nil`. Costs 1 bit. | `u8?` |
| `T[]`, `T[min..max]`, `T[n]` | An array of `T`. `T[n]` is exactly `n` long. | `u8[0..16]` |
| `{ [K]: V }`, `{ [K]: V }(min..max)` | A table from keys to values. A key can be any type in the first table except `unknown`, or a plain enum. | `{ [u8]: boolean }(0..64)` |
| `set<T>`, `set<T>(min..max)` | A table `{ [T]: true }`. | `set<u8>(0..64)` |
| `struct { a: T, b: U }` | A table with these fields. | `struct { name: string(1..16), level: u8 }` |
| `enum { A, B }` | One of the strings `"A"` and `"B"`. | `enum { Red, Blue }` |
| `enum "tag" { A { ... }, B { ... } }` | A table whose `tag` field names the variant, plus that variant's fields, such as `{ kind = "Sword", damage = 10 }`. | `enum "kind" { Sword { damage: u8 }, Bow { range: u16 } }` |
| `A \| B` | A value of either type. | `u8 \| string(0..16)` |
| a name | A named type, declared below. | `Stack` |

An array of booleans is packed into bits: `boolean[8]` takes one byte. A map or a set refuses a duplicate key.

Volt picks a member of `A | B` by the value's Luau type, so the members must be told apart that way. Two number types, two strings, two buffers, two tables (structs, arrays, maps, sets and tagged enums all count) or two instances cannot share a union, and the compiler says so. To choose between two structs, use a tagged enum. `nil` is never a member; use `?` instead. A literal counts as its Luau type, so `u8 | "none"` works, while `"on" | "off"` is two strings and is written `enum { on, off }` instead.

Give a type a name to use it in several places:

```
type Reference = string(1..64)
struct Stack { item: string(1..32), quantity: u16(1..999) }
enum Team { Red, Blue }
export struct Save { version: u16, stacks: Stack[0..256] }
```

`type`, `struct` and `enum` declare a name the whole schema can use. A named type also becomes a Luau type in the generated modules. `export` in front adds a `write` and a `read` for that type to the module (see [More tools](#more-tools)).

`@private` in front of a `type`, `struct` or `enum` keeps its Luau type to the generated modules: they still use it in their own signatures, but your scripts cannot name it. It changes nothing that is sent. An exported type cannot be private, since its `write` and `read` are for your scripts.

```
@private type Line = string.utf8(0..16384)
```

A namespace groups messages and types:

```
namespace Combat {
	event Hit {
		from: Client,
		type: Reliable,
		call: SingleSync,
		data: (target: u16, damage: u8),
	}
}
```

The event is then `Network.Combat.Hit`, and the client fires it with `Network.Combat.Hit.fire(12, 30)`. Outside the namespace a name inside it is written `Combat.Name`. A name declared at the top of the file can be used inside every namespace. A type and a message cannot share a name.

Generics, recursive types and struct spread are not part of the language, and the compiler reports them as errors.

## Choosing how a message travels

### Events or functions

Use an event when the sender does not need an answer: a player pressed a button, the round started, a door opened. Events can go either way, or both ways with `from: Both`.

Use a function when a player needs the server's answer before going on: buying an item, loading an inventory. Functions go from a client to the server only.

### Reliable or unreliable

A reliable message always arrives, exactly once, in the order it was fired. Use it for almost everything.

An unreliable message can be lost, and unreliable messages are not kept in order. Use it for something sent many times a second where the next message replaces the last, such as a position. Each unreliable message must fit in 900 bytes (`unreliableBudget` in [Options](#options)), and the compiler refuses one that could be larger, or that has no largest size at all, such as one with a string that has no range.

### Listener modes

`call` picks how listeners run.

| Mode | Listeners | Where each listener runs | Use it when |
|---|---|---|---|
| `SingleSync` | one | right away, inside the loop that reads the packet | one system owns the event and its listener never waits, such as hit registration, where the first packet to arrive is handled first |
| `ManySync` | any number, called in the order they connected | right away, inside the loop | several systems watch the event and none of them waits |
| `SingleAsync` | one | on a new thread for each message | one system owns the event and its listener may wait |
| `ManyAsync` | any number | on a new thread for each listener and message | several systems watch the event and some of them wait |
| `Polling` | none | your code reads the queue with `iter` | you want to handle the messages at a time you pick, such as once a frame |

A sync listener must not wait: no `task.wait`, no `WaitForChild`, no DataStore call. If one does, Volt reports a `listener` failure naming the event, and the rest of that packet waits until the listener resumes. The fix is in the listener, or in making the event `Async`. An error in a sync listener is reported the same way, and the packet goes on.

An async listener may wait. Each message costs one new thread per listener, and an error goes to the Output like any other thread's.

A function's handler always runs on its own thread.

## Safety defaults

Volt checks everything the server receives, and these checks cannot be turned off.

### Every value is checked

The server reads a packet from a player only after checking that it is a buffer, that it is at most 8,192 bytes (`maxPacket`), and that the player has sent at most 240 packets in the last second (`maxPacketsPerSecond`). Then it checks every value in every message against the schema: each number in its range and never NaN, each length within its bounds, each enum value known, each instance present and of its class, no key twice in a map or a set.

The sending side checks your values too, before anything is written, so a bad value raises an error where you fire it. `option writeValidation = false` removes those sending checks for speed. The receiving checks stay.

### Rate limits

Each event a client fires is limited to 120 messages per second per player, and each function to 60 calls per second per player. Change them in the schema:

```
event Ping {
	from: Client,
	type: Reliable,
	call: SingleAsync,
	data: u8,
	rate: 30,
}
```

`rate: unlimited` turns the limit off for one message. `option rate = 200` and `option functionRate = 30` change the defaults for the whole schema.

The server can also change a limit while the game runs. The second number is how many a player may save up, and it defaults to the first:

```lua
-- Let each player send 30 Pings a second, and save up at most 60
Network.rate("Ping", 30, 60)
```

On the client, `Network.rate` does nothing. A message over its rate is read and then dropped, and the rest of its packet goes on. A function call over its rate is answered with the reason `rate limited`.

### What happens to a bad packet

A message that fails a check is dropped along with the rest of its packet, because Volt can no longer tell where the next message starts. Your listener never sees it. Volt counts it and reports a `decode` failure.

### The schema-mismatch kick

Each module carries its schema's hash. When a client starts, the first thing it sends is that hash, a step called the handshake. If the hash differs from the server's, the server kicks the player with both hashes in the message. A client built from a different schema would read every message wrongly, so Volt stops it before it reads anything. This usually means one side's module is stale: compile again and publish both.

The server reads nothing from a player until their handshake arrives. Reliable messages it fires at them before then are held and sent, in order, right after the handshake. Unreliable ones are dropped.

### Failure kinds

Every problem Volt finds is a failure of one of nine kinds. Each one is counted, then handed to the failure handler.

| Kind | Cause | Scope | What happens | Default handling |
|---|---|---|---|---|
| `packet` | A packet that is not a buffer or is over `maxPacket`; one sent before the handshake or by a player who has left; a message id cut short or naming no message; a second handshake | packet | the packet is dropped, or the rest of it for a bad id | warn |
| `rate` | Over `maxPacketsPerSecond`, or over an event's or a function's `rate` | packet for the packet rate, message for a message's rate | the packet is dropped, or the message is skipped | warn |
| `handshake` | The client's schema hash differs from the server's | packet | the packet is dropped | kick, with both hashes in the message; a warning for a bot |
| `decode` | Any other check while reading a message | message | the rest of the packet is dropped | warn |
| `listener` | A sync listener raised an error or waited | message | the packet goes on | warn |
| `handler` | A function's handler raised an error, or returned a value its `return` type does not allow | message | the caller gets the error as its reason | warn |
| `outgoing` | A player's outgoing data for one frame went past `maxOutgoing`; on the client, the reliable data for one frame went past `maxPacket`, which a call finds at its own `invoke` | packet | the message that went past it is dropped | warn |
| `queue` | A queue was full | message | the oldest message is dropped | warn, once per event |
| `departed` | A fire at a player who has left or whose handshake failed; an answer to a caller who has left | packet | the message is dropped | nothing |

The default handler's warning reads `Volt: <kind> failure from <Name>: <detail>`, or `from a bot` for a bot, and `Volt: <kind> failure: <detail>` on the client. It warns at most once a minute per player and kind, so an attack cannot flood the Output, while the counts stay exact.

The detail of a message-scoped failure (a `rate` on a message, `decode`, `listener`, `handler` and `queue`) starts with the message's name, a colon and a space, exactly once, as in `Ping: over 120 a second`. A message in a namespace gives its full name, such as `Combat.Hit: ...`. The detail of a packet-scoped failure names no message, as in `over 240 packets a second`.

### Handling failures yourself

`Network.onFailure(handler)` replaces the handler for every kind and returns the one it replaced, which the first time is Volt's default. Call that default for the kinds you leave to Volt:

```lua
local Volt = require(ReplicatedStorage.Packages.Volt)

local default: Volt.Failure

default = Network.onFailure(function(player, kind, detail)
	if kind == "rate" then
		return -- this game ignores rate failures
	end

	default(player, kind, detail)
end)
```

The handler receives the player, the kind and the detail. On the client the player is `nil`. The handler must not wait. If it raises an error, Volt warns `Volt: the failure handler raised: ...` and goes on.

### Counters

`Network.stats()` returns the counts for everything this module has sent and received, and on the server `Network.stats(player)` returns one player's share. Each holds `packetsIn`, `bytesIn`, `messagesIn`, `packetsOut`, `bytesOut`, `messagesOut`, `rejected` (messages a hook dropped) and `failures`, a count per kind. A kind appears in `failures` the first time it happens, so read it as `stats.failures.rate or 0`. The tables update as the game runs. A player's counts go with them when they leave, and after that `Network.stats(player)` reads all zeros.

## More tools

### Hooks

A hook runs before a message is sent or after one is received, and returning `false` drops the message. On the server:

```lua
-- Drop any Ping whose value is 0 before the listener sees it
Network.hooks.afterReceive("Ping", function(player, value)
	return value ~= 0
end)

-- Print every Pong just before it is sent
Network.hooks.beforeSend("Pong", function(target, value)
	print(`sending Pong {value}`)
	return true
end)
```

- `beforeSend(name, hook)` takes an event this side fires. The hook receives the target and the data. The target is the player for `fire`, the list or set for `fireList` and `fireSet`, and `nil` for `fireAll`, `fireExcept` and every fire on the client.
- `afterReceive(name, hook)` takes an event or function this side receives. The hook runs after the checks and the rate limit, before the queue, the listener or the handler, and receives the player (`nil` on the client) and the data. With `nil` as the name, the hook covers every message and runs before the message's own hook.
- Each slot holds one hook. Registering again replaces it, and passing `nil` clears it.
- A dropped message is counted in `stats().rejected`, and in `stats(player).rejected` when the hook had a player. It is not a failure.
- A function call a hook drops gets no answer, so its caller waits until the timeout.
- A hook must not wait.

### Exported serializers

`export` in front of a type gives the module a `write` and a `read` for it. A serializer turns a value into bytes and back, which is how you can keep a value in a DataStore or send it some other way. Add this to `Game.volt`:

```
-- A player's progress, turned into a buffer and back
export struct Save {
	coins: u32,
	level: u16,
}
```

Then, on either side:

```lua
local packet, side = Network.Save.write({ coins = 250, level = 3 })
local save = Network.Save.read(packet, side)
print(save.coins, save.level)
```

This prints `250 3`. `packet` is a 6-byte buffer. `side` holds the instances and `unknown` values that travel beside the buffer, and it is `nil` here because `Save` has none. `write` refuses a bad value the way a fire does, and `read` checks every byte the way a received message is checked, raising an error on anything wrong. Neither one sends anything.

### Player callbacks

The server module tells you about each player:

```lua
-- Runs once Volt has set up a player, and at once for every player already set up
Network.onJoin(function(player)
	print(`{player.Name} joined`)
end)

-- Runs once the player's client has connected and what was held for them has gone out
Network.onHandshake(function(player)
	Network.Pong.fire(player, 0)
end)

-- Runs just before Volt forgets the player
Network.onLeave(function(player)
	local stats = Network.stats(player)
	print(`{player.Name} sent {stats.messagesIn} messages`)
end)
```

Each one returns a function that disconnects it, and each callback runs on its own thread. `onHandshake` runs at the end of the first flush after the player's handshake is accepted, once that flush has sent the messages held for them. A fire inside it goes out with the next flush, so the player hears it after the held messages. A player who leaves before that flush never reaches `onHandshake`.

`Network.traffic(player)` returns two numbers: the bytes sent to that player in the last second, across every Volt schema on the server (scripts inside an Actor count their own), and the bytes written for them that have not been sent yet.

### Looking up messages by name

`Network.events`, `Network.functions` and `Network.exports` map each full name to the same entry the module has: `Network.events["Combat.Hit"]` is `Network.Combat.Hit`, and `Network.exports["Save"]` is `Network.Save`. A name that does not exist gives `nil`. This lets a framework connect messages by name.

### Bots

A bot is a stand-in player that only exists on the server. Every server module treats it as a player, with its own counters, rate limits and handshake, so code that drives a bot goes through the same checks a player's client does. On the server of a running game:

- `Volt.addBot(name)` adds a bot to every Volt schema on the server, including ones started later.
- `Volt.removeBot(bot)` removes it, and every server module hears it leave.
- `Volt.connectBot(bot, scope)` returns the client side of one scope for the bot, which a test harness starts a client module on.

A bot is a table `{ Name = name }`, with no `UserId` and no `Kick`. A listener's player can be a bot, so strict code checks before it uses what only a `Player` has. `Network.isBot(value)` tells them apart. Volt never kicks a bot, and its warnings say `from a bot`.

### The mock transport

The mock lets you test your networking without Studio. It stands in for the remotes and keeps every packet in memory. A transport is whatever carries a side's packets; the real one uses the remotes.

- `Volt.mock(spawn)` makes a mock. Pass the scheduler: `task.spawn` from `@lune/task` under Lune, or Roblox's own `task.spawn` in Studio.
- `mock.server` is the server's transport.
- `mock.players` is the list of players.
- `mock:join(name)` adds a player, tells the server, and returns the player and that player's client transport.
- `mock:leave(player)` tells the server the player is leaving, then forgets them.
- A player's `Kick(message)` keeps the message in `player.kicked` and makes the player leave.
- `mock:step()` moves time forward one frame.
- `mock:addBot(name)`, `mock:removeBot(bot)` and `mock:connectBot(bot)` work like the `Volt` functions above. `mock.players`, `join`, `leave` and `step` never see a bot.
- `Volt.start(schema, transport)` starts a runtime over the transport given instead of the remotes.

A generated module calls `Volt.start(schema)` itself, so a test loads the module with a `require` that hands back a Volt whose `start` passes the mock's transport. This test runs under [Lune](https://github.com/lune-org/lune), which you can add with `rokit add lune-org/lune`. It needs an alias named `volt` in your `.luaurc` that points at the folder holding Volt's `init.luau`:

```lua
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local Volt = require("@volt")

-- Answers every index with itself, so ReplicatedStorage.Packages.Volt resolves to something
local anything = setmetatable({}, {
	__index = function(self)
		return self
	end,
})

-- Loads a generated module so that its Volt.start runs over the transport given
local function load(path: string, transport: Volt.Transport): any
	local environment = {
		game = {
			GetService = function()
				return anything
			end,
		},

		require = function()
			return {
				start = function(schema)
					return Volt.start(schema, transport)
				end,
			}
		end,
	}

	return luau.load(fs.readFile(path), { debugName = path, environment = environment })()
end

local mock = Volt.mock(task.spawn)
local server = load("src/Shared/Network/Server.luau", mock.server)

local alice, aliceTransport = mock:join("Alice")
local client = load("src/Shared/Network/Client.luau", aliceTransport)

server.Ping.on(function(player, value)
	server.Pong.fire(player, value + 1)
end)

local heard = nil
client.Pong.on(function(value)
	heard = value
end)

client.Ping.fire(7)

mock:step() -- the client's Heartbeat sends the Ping
mock:step() -- the server hears it, and its Heartbeat sends the Pong
mock:step() -- the client hears the Pong

assert(heard == 8, "the client should have heard Pong 8")

alice:Kick("Round over")

assert(alice.kicked == "Round over")
assert(#mock.players == 0)

print("passed")
```

A bot joins the same way, through its own client transport:

```lua
local bot = mock:addBot("Helper")
local botClient = load("src/Shared/Network/Client.luau", mock:connectBot(bot))

botClient.Ping.fire(3) -- the server's Ping listener hears it from the bot on the next step
```

Each `mock:step()` first delivers every packet that earlier flushes queued, in both directions, then fires one Heartbeat on every runtime, which is when each one sends. So with `flush = 1`, a fire made outside `step` reaches the other side on the second step, as the test above shows. A server fire at a player who has not handshaken waits for the step after their handshake arrives.

The mock differs from the real engine in six ways, which a test that leans on it must know:

1. A server packet for a player with no client runtime is dropped at the next step, where the engine keeps it until the client connects. Holding reliable messages until the handshake makes this rarely matter.
2. Callbacks for a joining player run at once inside `mock:join`, in the order they were registered, before `join` returns the client transport.
3. Reliable and unreliable packets share one queue per direction, which keeps their order and never loses one.
4. Each side holds one receiver per player. A second server runtime on one mock, or a second client runtime for one player, replaces the first. Two scopes cannot share a mock, so a test with several scopes uses one mock per scope and translates players between them.
5. Players are plain tables, `{ Name, UserId, Kick, kicked }`, not frozen, and the same table reaches every callback, handler and listener, so a test may add fields to one.
6. Heartbeat callbacks get no `deltaTime`.

## Colors in VS Code

Volt comes with a small VS Code extension that colors `.volt` files. It colors comments, strings, keywords such as `event` and `struct`, types such as `u8` and `Vector3`, the keys of an event or a function, fixed values such as `Reliable` and `SingleSync`, attributes such as `@private`, and numbers. It also marks the two mistakes `volt` finds while it reads a file character by character, a string with no closing quote and a character the language never uses, such as `$`, from that point to the end of the line; most themes show them in red. Toggle Line Comment (Ctrl+/) writes `--`, and VS Code closes brackets and quotes as you type.

The extension is not in the Wally package and not on the VS Code Marketplace. It lives in Volt's repository, in the folder `.vscode/volt-syntax`, so you need a copy of the repository on your computer, for example from `git clone https://github.com/Fadeluc-123/Volt.git`. It is three small JSON files, with nothing to build.

Install it once on each computer:

1. Open VS Code. Any folder can be open, or none.
2. Open the Command Palette with Ctrl+Shift+P (Cmd+Shift+P on a Mac).
3. Type `Developer: Install Extension from Location...` and press Enter.
4. In the folder picker, go into Volt's repository folder, then into `.vscode`, select the folder `volt-syntax` and confirm. On a Mac the picker hides folders whose name starts with a dot until you press Cmd+Shift+. (period).
5. Open any `.volt` file. The language name at the right of the status bar, along the bottom of the window, reads `Volt`, and the file is colored.

VS Code uses the folder where it lies instead of copying it, so one install colors `.volt` files in every project you open on that computer. Two things follow from that:

- After the extension's files change, for example when you pull a newer Volt or edit the grammar, open the Command Palette and run `Developer: Reload Window`, and VS Code reads the new files.
- If you move or delete Volt's folder, the colors stop. Install the extension again from the folder's new place.

If a `.volt` file is colored as some other language, another extension claims `.volt` too; one for Phalcon's Volt templates uses the same file extension. Click the language name in the status bar, choose `Configure File Association for '.volt'...` and pick `Volt`.

## Options

Options go at the top of a schema, one per line: `option name = value`. A path to a module is written with dots and starts with a service, such as `ReplicatedStorage.Packages.Volt`.

| Option | Default | What it does |
|---|---|---|
| `clientOutput` | required | Where the client module is written, relative to the schema file (the options file, for a folder) |
| `serverOutput` | required | Where the server module is written |
| `typesOutput` | none | Where the types module is written; without it, none is written |
| `runtime` | `ReplicatedStorage.Packages.Volt` | Where the generated modules require the Volt runtime from |
| `scope` | the schema file's name | The folder under `ReplicatedStorage.Volt` that holds this schema's remotes |
| `casing` | `camel` | How the module's methods are named: `camel` (`fireAll`, `onFailure`), `pascal` (`FireAll`, `OnFailure`) or `snake` (`fire_all`, `on_failure`) |
| `writeValidation` | `true` | Whether the sending side checks values before writing them; the receiving side always does |
| `manualReplication` | `false` | When `true`, Volt does not send on Heartbeat, and your code calls `Network.flush()` |
| `flush` | `1` | Send every this many Heartbeats |
| `maxPacket` | `8192` | The largest reliable packet the server accepts from a player, in bytes; the client keeps each frame's reliable data under it too |
| `maxPacketsPerSecond` | `240` | Packets per second the server accepts from each player, both remotes together |
| `maxOutgoing` | `262144` | Bytes one player's outgoing data may hold in one frame; the message that goes past it is dropped |
| `unreliableBudget` | `900` | The most bytes in one unreliable remote call, and the largest an unreliable message may be |
| `queue` | `64` | How many messages wait per event for a listener or for `iter` |
| `rate` | `120` | Messages per second each player may fire per event; `unlimited` turns the limit off |
| `functionRate` | `60` | Calls per second each player may make per function; `unlimited` turns the limit off |
| `timeout` | `10` | Seconds before a call fails with `timeout`; decimals are allowed |
| `yield` | `coroutine` | How `invoke` waits: `coroutine` pauses the calling thread, and `promise` returns a Promise |
| `promise` | none | The path of your Promise library, such as `ReplicatedStorage.Packages.Promise`; required when `yield = promise` |

With `yield = promise`, `invoke` returns a Promise that resolves with the answer, with no `true` in front, or rejects with the reason.

Keys of an event:

| Key | Values | Default |
|---|---|---|
| `from` | `Client`, `Server`, `Both` | required |
| `type` | `Reliable`, `Unreliable` | required |
| `call` | `SingleSync`, `SingleAsync`, `ManySync`, `ManyAsync`, `Polling` | required |
| `data` | a type, or a parameter pack such as `(x: f32, y: f32)` | none; the event carries nothing |
| `queue` | a whole number | the `queue` option |
| `rate` | a whole number, or `unlimited` | the `rate` option; on a `Server` event it means nothing and the compiler warns |

Keys of a function:

| Key | Values | Default |
|---|---|---|
| `data` | a type, or a parameter pack | none |
| `return` | a type, or a parameter pack | none |
| `yield` | `Coroutine`, `Promise` | the `yield` option |
| `timeout` | a number of seconds | the `timeout` option |
| `rate` | a whole number, or `unlimited` | the `functionRate` option |

## Troubleshooting

```
Volt: Decree's schema was compiled by Volt 0.2.0 and the runtime is 0.1.3
```

A generated module was compiled by a `volt` whose version differs from the runtime's in its first two numbers, and `require` refuses it. The name before `'s schema` is the scope that needs updating: here a package called Decree, and for your own schema its file name, such as `Game`. Make the two versions match: compile your own schemas again with the `volt` that matches your runtime, or update the package or Volt so they agree.

```
Volt: schema mismatch (client 0x10E8CDEB, server 0x894D330D)
```

This is the message a player is kicked with when the client module and the server module came from different schemas. Run `volt` again and publish both modules. `volt Game.volt --check` in CI catches a stale module before it ships. Two different schemas that set the same `option scope` cause this too.

```
Volt: rate failure from Alice: Ping: over 120 a second
```

A player fired `Ping` more than 120 times in a second, and the server dropped the messages past the limit. If the game really needs more, raise `rate` on the event. Otherwise fire less often, for example once per change instead of once per frame.

```
Ping: expected u8
Input.dir: expected u8(0..8)
Echo: length out of range
```

A fire or an invoke was given a value its type does not allow, and nothing was sent. The text names the message, then the field for a parameter pack: `Input.dir` is the `dir` value of an event `Input` with `data: (dir: u8(0..8), jump: boolean)`. Fix the value, or change the type in the schema.

```
Volt: queue failure from Alice: Ping: queue full, oldest dropped
```

Messages for `Ping` arrived while nothing was listening, and more than 64 piled up. Connect the listener earlier, read a `Polling` event more often, or raise `queue`.

```
Pong: a listener is already connected
```

`on` was called twice for a `Single` event. Luau puts the position of the line in Volt that raised it in front of this text. Disconnect the first listener before connecting another, or make the event `ManySync` or `ManyAsync`. A function gives `Echo: a handler is already connected` the same way.

```
Volt: still waiting for ReplicatedStorage.Volt.Game
```

The client module has waited 10 seconds for remotes the server has not created, and it keeps waiting and warning. The server creates them when it first requires its module, so make sure a server Script requires `Server.luau`. The warning names `ReplicatedStorage.Volt` alone when no schema's server module has run.

```
The system cannot find the path specified. (os error 3)
```

On Windows, `volt` prints this when the folder an output option points into does not exist. Create the folder and run `volt` again. Other systems word the message differently.

```
Unknown type 'Volt.Runtime'
```

The type checker cannot see Volt's types. Run `rojo sourcemap` and `wally-package-types` as in [Install](#install), after every `wally install`.

## Versions

The compiler and the runtime share one version number, and you upgrade them together. This release is `0.1.0`.

Each generated module records the version of the `volt` that wrote it, and `Network.version` returns it. When a module is required, the runtime compares the first two numbers of that version with its own and refuses a module that differs, with the error in [Troubleshooting](#troubleshooting).

Wally reads `0.1.0` in `wally.toml` as any version from `0.1.0` up to, but not including, `0.2.0`. A patch release such as `0.1.1` never changes how a module talks to the runtime, the failure kinds or anything a script calls, so taking one is safe. Anything that would change them comes as a new second number, such as `0.2.0`, which the check at `require` catches.

To upgrade, change the version of `fadeluc-123/volt` in both `rokit.toml` and `wally.toml`, run `rokit install` and `wally install`, run the two type commands from [Install](#install), then run `volt` on every schema.

## Working on Volt

The compiler lives in `src/Compiler/` and runs under Lune. The runtime is the rest of `src/`, and it is the only part published to Wally. The tests are in `tests/`, with the schemas they compile in `tests/Schemas/` and the expected generated modules in `tests/Golden/`.

Install the tools pinned in `rokit.toml`, then use the scripts in `.lune/`:

```sh
rokit install
lune run test                 # every test; lune run test Functions runs only files whose name contains Functions
lune run test --update        # rewrites the golden files after a reviewed change to the generator
lune run analyze              # luau-lsp over the source, the tests and the generated modules
lune run format               # StyLua over every first-party file
lune run build                # the volt binaries and their archives, in build/
lune run bench                # the benchmark, compiled, built and run in Studio
selene src tests .lune place benchmark
```

Run the compiler from source with `lune run src/Compiler <schema>`.

The editor colors come from `.vscode/volt-syntax/syntaxes/volt.tmLanguage.json`. Four of its rules list words the compiler knows: `keyword` the lexer's keywords, `primitive` the rows of `src/Compiler/Config/Primitives.luau`, `roblox` the rows of `Config/Roblox.luau`, and `value` the fixed values in `Config/Options.luau`. `tests/Grammar.test.luau` fails when one of those lists and its source differ, printing both, so a word added to the compiler is added to its rule in the same change. The other rules match by shape and no test runs them, so after editing the grammar run `Developer: Reload Window` and read `tests/Schemas/Example.volt` and `tests/Schemas/Console.volt`; `Developer: Inspect Editor Tokens and Scopes` shows the scope of the text under the cursor.

The smoke place in `place/` checks real remotes in Studio:

```sh
lune run src/Compiler tests/Schemas/Smoke.volt
rojo build place/place.project.json -o Smoke.rbxl
```

Open `Smoke.rbxl`, start a test with "Start Server + 1 Player", and both Output windows print `Volt smoke: pass`.
