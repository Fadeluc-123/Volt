option clientOutput = "Client.luau"
option serverOutput = "Server.luau"

@depth(4) export struct Tree { name: string(0..8), kids: Tree[0..3] }
@depth(4) struct Folder { entries: Entry[0..3] }
@depth(4) enum Entry "kind" { File { size: u16 }, Sub { folder: Folder } }

event Scene { from: Client, type: Reliable, call: SingleSync, data: Tree }
event Files { from: Server, type: Reliable, call: SingleSync, data: Folder }
