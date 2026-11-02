# Volt benchmark

Run 2026-11-02 with zap 0.6.29, blink 0.18.9, volt 0.1.0.
Studio 0.745.0.7451137, 10 s per run, 32 payloads cycled.

## Entities (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 105.068 | - | 5700 | 0% |
| blink | 37 | 34 | 3.223 | 603.0 | 37 | 0% |
| zap | 37 | 36 | 11.038 | 603.0 | 37 | 0% |
| zapUnchecked | 39 | 39 | 10.751 | 603.0 | 39 | 0% |
| volt | 60 | 60 | 2.871 | 603.0 | 60 | 0% |
| voltUnchecked | 60 | 60 | 1.927 | 603.0 | 60 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 105.068 | - | -38.401 | 189.142 | 42 | 21.424 |
| blink | 27.027 | 3.223 | 0.328 | 23.475 | 25.558 | 37 | 0.082 |
| zap | 27.027 | 11.038 | 0.304 | 15.685 | 25.695 | 36 | 0.075 |
| zapUnchecked | 25.641 | 10.751 | 0.297 | 14.593 | 23.969 | 39 | 0.072 |
| volt | 16.667 | 2.871 | 0.447 | 13.349 | 6.777 | 59 | 0.063 |
| voltUnchecked | 16.667 | 1.927 | 0.426 | 14.314 | 6.698 | 59 | 0.047 |

## Booleans (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 45.438 | - | 10300 | 0% |
| blink | 59 | 56 | 7.648 | 1003.0 | 58 | 0% |
| zap | 45 | 41 | 19.592 | 1003.0 | 45 | 0% |
| zapUnchecked | 49 | 47 | 18.482 | 1003.0 | 48 | 0% |
| volt | 60 | 60 | 2.596 | 128.0 | 60 | 0% |
| voltUnchecked | 60 | 60 | 2.606 | 128.0 | 60 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 45.438 | - | 21.229 | 89.852 | 42 | 17.811 |
| blink | 16.949 | 7.648 | 0.575 | 8.726 | 12.969 | 58 | 0.059 |
| zap | 22.222 | 19.592 | 0.526 | 2.104 | 13.000 | 44 | 0.069 |
| zapUnchecked | 20.408 | 18.482 | 0.499 | 1.427 | 11.970 | 48 | 0.081 |
| volt | 16.667 | 2.596 | 0.107 | 13.963 | 3.358 | 59 | 0.047 |
| voltUnchecked | 16.667 | 2.606 | 0.108 | 13.953 | 3.419 | 59 | 0.046 |

## Snapshots (100 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 60 | 60 | 56.184 | - | 6010 | 0% |
| blink | 60 | 60 | 8.518 | 1425.6 | 60 | 0% |
| zap | 60 | 60 | 11.731 | 1425.6 | 60 | 0% |
| zapUnchecked | 60 | 60 | 11.778 | 1425.6 | 60 | 0% |
| volt | 60 | 60 | 4.568 | 1425.6 | 60 | 0% |
| voltUnchecked | 60 | 60 | 3.968 | 1425.6 | 60 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 16.667 | 5.618 | - | 11.048 | 100.527 | 59 | 2.545 |
| blink | 16.667 | 0.852 | 0.102 | 15.713 | 15.616 | 60 | 0.049 |
| zap | 16.667 | 1.173 | 0.103 | 15.390 | 16.762 | 59 | 0.049 |
| zapUnchecked | 16.667 | 1.178 | 0.113 | 15.376 | 18.624 | 59 | 0.049 |
| volt | 16.667 | 0.457 | 0.116 | 16.094 | 9.186 | 59 | 0.049 |
| voltUnchecked | 16.667 | 0.397 | 0.115 | 16.154 | 10.006 | 59 | 0.049 |

## Input (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 60 | 60 | 1.810 | - | 60100 | 0% |
| blink | 60 | 60 | 1.765 | 3.0 | 60100 | 0% |
| zap | 60 | 60 | 1.936 | 2.0 | 60100 | 0% |
| zapUnchecked | 60 | 60 | 2.212 | 2.0 | 60100 | 0% |
| volt | 60 | 60 | 0.150 | 3.0 | 240 | 0% |
| voltUnchecked | 60 | 60 | 0.201 | 3.0 | 240 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 16.667 | 1.810 | - | 14.857 | 3.499 | 60 | 0.047 |
| blink | 16.667 | 1.765 | 0.001 | 14.900 | 3.223 | 59 | 0.048 |
| zap | 16.667 | 1.936 | 0.001 | 14.729 | 3.259 | 59 | 0.048 |
| zapUnchecked | 16.667 | 2.212 | 0.001 | 14.453 | 3.749 | 59 | 0.048 |
| volt | 16.667 | 0.150 | 0.044 | 16.472 | 0.336 | 59 | 0.050 |
| voltUnchecked | 16.667 | 0.201 | 0.042 | 16.423 | 0.328 | 59 | 0.050 |

## Generated modules

| Library | Client | Server |
|---|---|---|
| Blink | 10.6 KB, 389 lines | 14.6 KB, 492 lines |
| Zap | 8.7 KB, 318 lines | 10.1 KB, 377 lines |
| ZapUnchecked | 8.4 KB, 310 lines | 10.2 KB, 377 lines |
| Volt | 9.3 KB, 373 lines | 9.5 KB, 340 lines |
| VoltUnchecked | 6.7 KB, 253 lines | 9.5 KB, 340 lines |
