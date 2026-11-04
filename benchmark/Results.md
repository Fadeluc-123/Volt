# Volt benchmark

Run 2026-11-04 with zap 0.6.29, blink 0.18.9, volt 0.1.0.
Studio 0.745.0.7451137, 10 s per run, 32 payloads cycled.

## Entities (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 88.450 | - | 6700 | 0% |
| blink | 44 | 43 | 2.850 | 603.0 | 43 | 0% |
| zap | 42 | 42 | 9.827 | 603.0 | 42 | 0% |
| zapUnchecked | 42 | 41 | 9.909 | 603.0 | 41 | 0% |
| volt | 60 | 59 | 2.522 | 603.0 | 60 | 0% |
| voltUnchecked | 60 | 60 | 1.671 | 603.0 | 60 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 88.450 | - | -21.784 | 159.786 | 42 | 21.110 |
| blink | 22.727 | 2.850 | 0.266 | 19.610 | 21.618 | 43 | 0.092 |
| zap | 23.810 | 9.827 | 0.284 | 13.698 | 22.397 | 42 | 0.072 |
| zapUnchecked | 23.810 | 9.909 | 0.292 | 13.609 | 22.638 | 41 | 0.071 |
| volt | 16.667 | 2.522 | 0.343 | 13.801 | 6.056 | 59 | 0.047 |
| voltUnchecked | 16.667 | 1.671 | 0.344 | 14.651 | 6.027 | 60 | 0.048 |

## Booleans (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 40.842 | - | 11500 | 0% |
| blink | 60 | 60 | 5.719 | 1003.0 | 60 | 0% |
| zap | 54 | 52 | 16.291 | 1003.0 | 53 | 0% |
| zapUnchecked | 54 | 53 | 16.111 | 1003.0 | 54 | 0% |
| volt | 60 | 60 | 2.397 | 128.0 | 60 | 0% |
| voltUnchecked | 60 | 60 | 2.829 | 128.0 | 60 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 40.842 | - | 25.825 | 78.674 | 41 | 17.077 |
| blink | 16.667 | 5.719 | 0.425 | 10.523 | 8.985 | 59 | 0.109 |
| zap | 18.519 | 16.291 | 0.469 | 1.758 | 10.456 | 53 | 0.096 |
| zapUnchecked | 18.519 | 16.111 | 0.466 | 1.942 | 10.433 | 54 | 0.130 |
| volt | 16.667 | 2.397 | 0.099 | 14.171 | 3.102 | 59 | 0.064 |
| voltUnchecked | 16.667 | 2.829 | 0.110 | 13.728 | 3.553 | 59 | 0.047 |

## Snapshots (100 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 60 | 60 | 46.939 | - | 6010 | 0% |
| blink | 60 | 60 | 8.198 | 1425.6 | 60 | 0% |
| zap | 60 | 60 | 11.340 | 1425.6 | 60 | 0% |
| zapUnchecked | 60 | 60 | 11.423 | 1425.6 | 60 | 0% |
| volt | 60 | 60 | 4.256 | 1425.6 | 60 | 0% |
| voltUnchecked | 60 | 60 | 3.620 | 1425.6 | 60 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 16.667 | 4.694 | - | 11.973 | 85.917 | 59 | 0.996 |
| blink | 16.667 | 0.820 | 0.104 | 15.743 | 14.567 | 59 | 0.049 |
| zap | 16.667 | 1.134 | 0.110 | 15.422 | 16.062 | 59 | 0.049 |
| zapUnchecked | 16.667 | 1.142 | 0.108 | 15.416 | 17.727 | 59 | 0.049 |
| volt | 16.667 | 0.426 | 0.113 | 16.128 | 8.358 | 59 | 0.049 |
| voltUnchecked | 16.667 | 0.362 | 0.110 | 16.195 | 8.387 | 59 | 0.049 |

## Input (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 60 | 60 | 1.605 | - | 60100 | 0% |
| blink | 60 | 60 | 1.704 | 3.0 | 60100 | 0% |
| zap | 60 | 60 | 1.777 | 2.0 | 60100 | 0% |
| zapUnchecked | 60 | 59 | 1.752 | 2.0 | 60100 | 0% |
| volt | 60 | 60 | 0.143 | 3.0 | 240 | 0% |
| voltUnchecked | 60 | 60 | 0.184 | 3.0 | 240 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 16.667 | 1.605 | - | 15.062 | 3.150 | 59 | 0.048 |
| blink | 16.667 | 1.704 | 0.001 | 14.962 | 3.344 | 59 | 0.048 |
| zap | 16.667 | 1.777 | 0.001 | 14.888 | 3.136 | 59 | 0.048 |
| zapUnchecked | 16.667 | 1.752 | 0.001 | 14.914 | 3.099 | 60 | 0.047 |
| volt | 16.667 | 0.143 | 0.044 | 16.480 | 0.294 | 59 | 0.050 |
| voltUnchecked | 16.667 | 0.184 | 0.043 | 16.440 | 0.294 | 59 | 0.050 |

## Generated modules

| Library | Client | Server |
|---|---|---|
| Blink | 10.6 KB, 389 lines | 14.6 KB, 492 lines |
| Zap | 8.7 KB, 318 lines | 10.1 KB, 377 lines |
| ZapUnchecked | 8.4 KB, 310 lines | 10.2 KB, 377 lines |
| Volt | 9.3 KB, 373 lines | 9.5 KB, 340 lines |
| VoltUnchecked | 6.7 KB, 253 lines | 9.5 KB, 340 lines |
