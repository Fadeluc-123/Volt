---
type: decision
date: 2026-09-20
session: 14e4b904
status: active
description: ByteNet is excluded from the Zap versus Blink comparison and stays out of scope for Volt's references and benchmarks.
tags: [volt, scope]
---
# ByteNet is out of scope
Up: [[Decisions]]

**Decision:** ByteNet was excluded from the 2026-09-20 comparison at Mike's request and stays out of scope. Volt's source references are Blink and Zap only.

**Alternatives:** none considered; ByteNet builds serializers from a schema table at runtime, which is the approach [[Research/how-buffer-networking-works]] explains generated code beats.

**Revisit when:** Mike says so. The Blink benchmark harness fetches ByteNet by default; leaving it in the comparison run as a fourth column is allowed but not required ([[Planning/volt-benchmark-plan]]).

**Consequences:** Research and the coverage matrix do not track ByteNet features or bugs.
Related: [[Research/zap-vs-blink-recommendation]]
