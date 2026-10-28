namespace Round {
	event Start {
		from: Server, type: Reliable, call: SingleAsync,
		data: (score: Score),
	}
}
