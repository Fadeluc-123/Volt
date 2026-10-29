# Volt benchmark

Run 2026-10-29 with zap 0.6.29, blink 0.18.9, volt 0.1.0.
Studio 0.745.0.7451137, 10 s per run, 32 payloads cycled.

## Entities (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 88.948 | - | 6500 | 0% |
| blink | 44 | 43 | 2.867 | 603.0 | 44 | 0% |
| zap | 42 | 40 | 9.617 | 603.0 | 42 | 0% |
| zapUnchecked | 42 | 42 | 9.475 | 603.0 | 42 | 0% |
| volt | 60 | 60 | 2.479 | 603.0 | 60 | 0% |
| voltUnchecked | 60 | 60 | 1.687 | 603.0 | 60 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 88.948 | - | -22.281 | 153.027 | 41 | 19.726 |
| blink | 22.727 | 2.867 | 0.265 | 19.595 | 21.501 | 43 | 0.091 |
| zap | 23.810 | 9.617 | 0.279 | 13.914 | 22.588 | 41 | 0.070 |
| zapUnchecked | 23.810 | 9.475 | 0.280 | 14.054 | 22.336 | 42 | 0.073 |
| volt | 16.667 | 2.479 | 0.367 | 13.820 | 5.391 | 59 | 0.047 |
| voltUnchecked | 16.667 | 1.687 | 0.346 | 14.634 | 5.292 | 60 | 0.048 |

## Booleans (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 39.877 | - | 11600 | 0% |
| blink | 60 | 59 | 5.640 | 1003.0 | 60 | 0% |
| zap | 57 | 56 | 15.238 | 1003.0 | 57 | 0% |
| zapUnchecked | 57 | 55 | 15.447 | 1003.0 | 57 | 0% |
| volt | 60 | 59 | 2.386 | 128.0 | 60 | 0% |
| voltUnchecked | 60 | 60 | 2.426 | 128.0 | 60 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 39.877 | - | 26.790 | 75.992 | 41 | 16.562 |
| blink | 16.667 | 5.640 | 0.425 | 10.601 | 8.992 | 59 | 0.110 |
| zap | 17.544 | 15.238 | 0.465 | 1.841 | 10.299 | 57 | 0.080 |
| zapUnchecked | 17.544 | 15.447 | 0.458 | 1.639 | 10.300 | 56 | 0.079 |
| volt | 16.667 | 2.386 | 0.088 | 14.193 | 3.220 | 59 | 0.047 |
| voltUnchecked | 16.667 | 2.426 | 0.089 | 14.151 | 3.315 | 59 | 0.047 |

## Snapshots (100 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 60 | 60 | 38.590 | - | 6010 | 0% |
| blink | 60 | 60 | 7.386 | 1425.6 | 60 | 0% |
| zap | 60 | 59 | 11.200 | 1425.6 | 60 | 0% |
| zapUnchecked | 60 | 60 | 10.875 | 1425.6 | 60 | 0% |
| volt | 60 | 60 | 4.228 | 1425.6 | 60 | 0% |
| voltUnchecked | 60 | 58 | 3.570 | 1425.6 | 59 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 16.667 | 3.859 | - | 12.808 | 73.373 | 60 | 0.079 |
| blink | 16.667 | 0.739 | 0.089 | 15.839 | 13.036 | 59 | 0.049 |
| zap | 16.667 | 1.120 | 0.095 | 15.452 | 15.568 | 59 | 0.049 |
| zapUnchecked | 16.667 | 1.088 | 0.101 | 15.478 | 16.623 | 59 | 0.049 |
| volt | 16.667 | 0.423 | 0.106 | 16.138 | 8.839 | 60 | 0.033 |
| voltUnchecked | 16.667 | 0.357 | 0.105 | 16.204 | 9.315 | 59 | 0.049 |

## Input (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 60 | 60 | 1.561 | - | 60100 | 0% |
| blink | 60 | 60 | 1.698 | 3.0 | 60100 | 0% |
| zap | 60 | 59 | 1.770 | 2.0 | 60100 | 0% |
| zapUnchecked | 60 | 59 | 1.818 | 2.0 | 60100 | 0% |
| volt | 60 | 60 | 0.144 | 3.0 | 240 | 0% |
| voltUnchecked | 60 | 59 | 0.187 | 3.0 | 240 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 16.667 | 1.561 | - | 15.106 | 3.191 | 59 | 0.048 |
| blink | 16.667 | 1.698 | 0.001 | 14.967 | 4.090 | 60 | 0.047 |
| zap | 16.667 | 1.770 | 0.001 | 14.895 | 3.890 | 60 | 0.048 |
| zapUnchecked | 16.667 | 1.818 | 0.001 | 14.848 | 4.158 | 59 | 0.048 |
| volt | 16.667 | 0.144 | 0.040 | 16.483 | 0.308 | 59 | 0.050 |
| voltUnchecked | 16.667 | 0.187 | 0.037 | 16.443 | 0.300 | 59 | 0.050 |

## Generated modules

| Library | Client | Server |
|---|---|---|
| Blink | 10.6 KB, 389 lines | 14.6 KB, 492 lines |
| Zap | 8.7 KB, 318 lines | 10.1 KB, 377 lines |
| ZapUnchecked | 8.4 KB, 310 lines | 10.2 KB, 377 lines |
| Volt | 9.3 KB, 373 lines | 9.4 KB, 336 lines |
| VoltUnchecked | 6.7 KB, 253 lines | 9.4 KB, 336 lines |
