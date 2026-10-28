namespace Combat {
	event Strike {
		from: Client, type: Reliable, call: SingleSync,
		data: Hit,
	}
}
