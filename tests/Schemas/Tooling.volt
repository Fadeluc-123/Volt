option clientOutput = "Client.luau"
option serverOutput = "Server.luau"
option inspectorOutput = "Inspector.luau"
option profileLabels = true

enum Kind { Info, Warn }
struct Entry { name: string(1..16), kind: Kind }

event Sync { from: Both, type: Reliable, call: SingleSync, data: u8 }
event Post { from: Client, type: Unreliable, call: ManySync, data: Entry }
event Seen { from: Server, type: Reliable, call: SingleAsync, data: (who: Instance, entry: Entry) }

function Lookup { data: string(1..16), return: Entry? }
