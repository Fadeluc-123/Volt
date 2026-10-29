# Volt benchmark

Run 2026-10-29 with zap 0.6.29, blink 0.18.9, volt 0.1.0.
Studio 0.745.0.7451137, 10 s per run, 32 payloads cycled.

## Entities (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 80.594 | - | 7100 | 0% |
| blink | 44 | 42 | 2.889 | 603.0 | 44 | 0% |
| zap | 43 | 42 | 9.584 | 603.0 | 43 | 0% |
| zapUnchecked | 42 | 42 | 9.444 | 603.0 | 42 | 0% |
| volt | 60 | 60 | 2.543 | 603.0 | 60 | 0% |
| voltUnchecked | 60 | 60 | 1.697 | 603.0 | 60 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 80.594 | - | -13.927 | 145.697 | 42 | 20.635 |
| blink | 22.727 | 2.889 | 0.274 | 19.564 | 21.465 | 44 | 0.076 |
| zap | 23.256 | 9.584 | 0.304 | 13.367 | 21.874 | 43 | 0.075 |
| zapUnchecked | 23.810 | 9.444 | 0.289 | 14.077 | 22.264 | 42 | 0.077 |
| volt | 16.667 | 2.543 | 0.392 | 13.732 | 5.606 | 59 | 0.047 |
| voltUnchecked | 16.667 | 1.697 | 0.353 | 14.616 | 5.578 | 60 | 0.047 |

## Booleans (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 39.430 | - | 11600 | 0% |
| blink | 60 | 60 | 6.293 | 1003.0 | 60 | 0% |
| zap | 57 | 53 | 15.192 | 1003.0 | 56 | 0% |
| zapUnchecked | 57 | 56 | 15.091 | 1003.0 | 56 | 0% |
| volt | 60 | 60 | 2.395 | 128.0 | 60 | 0% |
| voltUnchecked | 60 | 59 | 2.458 | 128.0 | 60 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 39.430 | - | 27.237 | 77.876 | 42 | 17.039 |
| blink | 16.667 | 6.293 | 0.428 | 9.946 | 9.038 | 59 | 0.110 |
| zap | 17.544 | 15.192 | 0.495 | 1.856 | 10.278 | 56 | 0.114 |
| zapUnchecked | 17.544 | 15.091 | 0.499 | 1.954 | 10.237 | 56 | 0.113 |
| volt | 16.667 | 2.395 | 0.095 | 14.177 | 2.992 | 59 | 0.047 |
| voltUnchecked | 16.667 | 2.458 | 0.095 | 14.114 | 2.996 | 59 | 0.047 |

## Snapshots (100 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 60 | 60 | 37.835 | - | 6010 | 0% |
| blink | 60 | 59 | 7.676 | 1425.6 | 60 | 0% |
| zap | 60 | 60 | 10.961 | 1425.6 | 60 | 0% |
| zapUnchecked | 60 | 60 | 10.826 | 1425.6 | 60 | 0% |
| volt | 60 | 60 | 4.355 | 1425.6 | 60 | 0% |
| voltUnchecked | 60 | 59 | 3.713 | 1425.6 | 60 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 16.667 | 3.783 | - | 12.883 | 67.958 | 59 | 0.046 |
| blink | 16.667 | 0.768 | 0.091 | 15.809 | 13.335 | 59 | 0.066 |
| zap | 16.667 | 1.096 | 0.097 | 15.473 | 14.926 | 59 | 0.048 |
| zapUnchecked | 16.667 | 1.083 | 0.097 | 15.487 | 16.581 | 59 | 0.065 |
| volt | 16.667 | 0.436 | 0.122 | 16.109 | 8.893 | 60 | 0.049 |
| voltUnchecked | 16.667 | 0.371 | 0.115 | 16.181 | 8.686 | 59 | 0.049 |

## Input (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 60 | 59 | 1.483 | - | 60100 | 0% |
| blink | 60 | 60 | 1.639 | 3.0 | 60100 | 0% |
| zap | 60 | 60 | 1.763 | 2.0 | 60100 | 0% |
| zapUnchecked | 60 | 60 | 1.717 | 2.0 | 60100 | 0% |
| volt | 60 | 60 | 0.152 | 3.0 | 240 | 0% |
| voltUnchecked | 60 | 60 | 0.180 | 3.0 | 240 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 16.667 | 1.483 | - | 15.183 | 3.036 | 60 | 0.048 |
| blink | 16.667 | 1.639 | 0.001 | 15.027 | 4.076 | 60 | 0.049 |
| zap | 16.667 | 1.763 | 0.001 | 14.903 | 3.955 | 59 | 0.033 |
| zapUnchecked | 16.667 | 1.717 | 0.001 | 14.948 | 4.001 | 59 | 0.048 |
| volt | 16.667 | 0.152 | 0.039 | 16.476 | 0.307 | 59 | 0.066 |
| voltUnchecked | 16.667 | 0.180 | 0.037 | 16.449 | 0.295 | 59 | 0.050 |

## Generated modules

| Library | Client | Server |
|---|---|---|
| Blink | 10.6 KB, 389 lines | 14.6 KB, 492 lines |
| Zap | 8.7 KB, 318 lines | 10.1 KB, 377 lines |
| ZapUnchecked | 8.4 KB, 310 lines | 10.2 KB, 377 lines |
| Volt | 9.3 KB, 373 lines | 9.4 KB, 336 lines |
| VoltUnchecked | 6.7 KB, 253 lines | 9.4 KB, 336 lines |
