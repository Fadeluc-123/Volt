# Volt benchmark

Run 2026-09-22 with zap 0.6.29, blink 0.18.9, volt 0.1.0.
Studio 0.740.0.7400927, 10 s per run, 32 payloads cycled. Idle 170 FPS; with the server spinning 2 ms a frame 198 FPS, a client frame -0.832 ms longer.

## Entities (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 121.573 | - | 4400 | 0% |
| blink | 190 | 178 | 3.313 | 603.0 | 191 | 0% |
| zap | 74 | 73 | 12.064 | 603.0 | 74 | 0% |
| zapUnchecked | 74 | 71 | 12.077 | 603.0 | 73 | 0% |
| volt | 183 | 173 | 3.877 | 603.0 | 182 | 0% |
| voltUnchecked | 209 | 203 | 2.659 | 603.0 | 211 | 0% |

Where a frame goes, in milliseconds: the fires, the flush, what the server spent receiving in a frame of its own, and the rest.

| Library | Frame | Fires | Flush | Receive | Other | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 121.573 | - | 8.033 | -62.940 | 149 | 2.920 |
| blink | 5.263 | 3.313 | 0.220 | 46.552 | -44.822 | 191 | 81.449 |
| zap | 13.514 | 12.064 | 0.180 | 42.298 | -41.028 | 74 | 22.149 |
| zapUnchecked | 13.514 | 12.077 | 0.179 | 41.576 | -40.318 | 73 | 21.550 |
| volt | 5.464 | 3.877 | 0.289 | 10.700 | -9.403 | 144 | 7.098 |
| voltUnchecked | 4.785 | 2.659 | 0.295 | 10.732 | -8.902 | 176 | 11.076 |

## Booleans (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 57.971 | - | 7000 | 0% |
| blink | 111 | 103 | 7.207 | 1003.0 | 109 | 0% |
| zap | 48 | 47 | 19.304 | 1003.0 | 47 | 0% |
| zapUnchecked | 47 | 47 | 19.425 | 1003.0 | 47 | 0% |
| volt | 206 | 191 | 3.537 | 128.0 | 206 | 0% |
| voltUnchecked | 206 | 201 | 3.626 | 128.0 | 205 | 0% |

Where a frame goes, in milliseconds: the fires, the flush, what the server spent receiving in a frame of its own, and the rest.

| Library | Frame | Fires | Flush | Receive | Other | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 57.971 | - | 7.493 | 1.203 | 116 | 0.129 |
| blink | 9.009 | 7.207 | 0.347 | 12.878 | -11.422 | 109 | 5.461 |
| zap | 20.833 | 19.304 | 0.296 | 13.201 | -11.968 | 47 | 0.063 |
| zapUnchecked | 21.277 | 19.425 | 0.297 | 13.573 | -12.018 | 47 | 0.059 |
| volt | 4.854 | 3.537 | 0.079 | 5.421 | -4.183 | 161 | 0.082 |
| voltUnchecked | 4.854 | 3.626 | 0.078 | 4.805 | -3.655 | 180 | 0.017 |

## Snapshots (100 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 88 | 86 | 55.372 | - | 8830 | 0% |
| blink | 197 | 194 | 9.002 | 1425.6 | 204 | 0% |
| zap | 214 | 177 | 14.346 | 1425.6 | 211 | 0% |
| zapUnchecked | 221 | 204 | 14.088 | 1425.6 | 223 | 0% |
| volt | 215 | 197 | 6.932 | 1425.6 | 213 | 0% |
| voltUnchecked | 206 | 193 | 5.893 | 1425.6 | 207 | 0% |

Where a frame goes, in milliseconds: the fires, the flush, what the server spent receiving in a frame of its own, and the rest.

| Library | Frame | Fires | Flush | Receive | Other | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 11.364 | 5.537 | - | 7.975 | -2.149 | 130 | 1.223 |
| blink | 5.076 | 0.900 | 0.099 | 2.788 | 1.289 | 191 | 0.021 |
| zap | 4.673 | 1.435 | 0.100 | 2.942 | 0.196 | 197 | 0.017 |
| zapUnchecked | 4.525 | 1.409 | 0.116 | 3.205 | -0.205 | 206 | 0.012 |
| volt | 4.651 | 0.693 | 0.146 | 1.878 | 1.933 | 203 | 0.010 |
| voltUnchecked | 4.854 | 0.589 | 0.148 | 1.885 | 2.232 | 199 | 0.011 |

## Input (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 205 | 203 | 2.498 | - | 207600 | 0% |
| blink | 205 | 200 | 2.572 | 3.0 | 206100 | 0% |
| zap | 202 | 201 | 2.650 | 2.0 | 205200 | 0% |
| zapUnchecked | 202 | 185 | 2.659 | 2.0 | 201600 | 0% |
| volt | 199 | 176 | 0.293 | 3.0 | 795 | 0% |
| voltUnchecked | 178 | 168 | 0.496 | 3.0 | 735 | 0% |

Where a frame goes, in milliseconds: the fires, the flush, what the server spent receiving in a frame of its own, and the rest.

| Library | Frame | Fires | Flush | Receive | Other | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 4.878 | 2.498 | - | 8.053 | -5.673 | 124 | 0.663 |
| blink | 4.878 | 2.572 | 0.001 | 7.995 | -5.690 | 129 | 1.001 |
| zap | 4.950 | 2.650 | 0.001 | 7.981 | -5.681 | 124 | 0.588 |
| zapUnchecked | 4.950 | 2.659 | 0.001 | 7.927 | -5.637 | 128 | 0.932 |
| volt | 5.025 | 0.293 | 0.057 | 0.870 | 3.804 | 197 | 0.013 |
| voltUnchecked | 5.618 | 0.496 | 0.065 | 1.003 | 4.053 | 178 | 0.010 |

## Generated modules

| Library | Client | Server |
|---|---|---|
| Blink | 10.6 KB, 389 lines | 14.6 KB, 492 lines |
| Zap | 8.7 KB, 318 lines | 10.1 KB, 377 lines |
| ZapUnchecked | 8.4 KB, 310 lines | 10.2 KB, 377 lines |
| Volt | 9.0 KB, 367 lines | 8.4 KB, 310 lines |
| VoltUnchecked | 6.4 KB, 247 lines | 8.4 KB, 310 lines |
