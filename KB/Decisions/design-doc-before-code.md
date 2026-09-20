---
type: decision
date: 2026-09-20
session: 14e4b904
status: active
description: No package code is written before the design document is reviewed by Mike, and nothing under Reference/ is modified.
tags: [volt, process]
---
# No package code before the design document is reviewed
Up: [[Decisions]]

**Decision:** Do not start writing the package before the design document has been written and reviewed by Mike. Do not modify anything under `Reference/` (the read-only source snapshots); re-fetch from GitHub if a newer version is needed.

**Alternatives:** prototype first (rejected: the expensive part is the compiler, and the design document is what keeps its scope honest).

**Revisit when:** Mike approves the design document; that approval is what unlocks implementation.

**Consequences:** Sessions before that point produce research, the coverage matrix, the design document, the benchmark plan and name verification ([[Planning/volt-next-session-deliverables]]). A benchmark harness may be built because it measures the existing libraries, not Volt.
Related: [[Decisions/build-from-scratch-not-fork]] [[Research/reference-source-snapshots]]
