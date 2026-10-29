# Volt benchmark, Server & Clients

Runs started by hand from the Test tab, Clients and Servers with one player, and pasted from the client's Output, since run-in-roblox captures only the Studio it launched. `lune run bench` rewrites `Results.md` whole and never touches this file. Oldest first.

## Server & Clients, one player

The same place started from the Test tab as a local server and one client, two Studio processes, so the client's frame is its own and the server's frame carries its receive. Pasted from the client's Output on 2026-09-22; the Receive and Server FPS columns are as this run's harness defined them, a span per busy server frame and busy frames over the seconds between consecutive ones.

Studio 0.740.0.7400927, 10 s per run, 32 payloads cycled. Idle 75 FPS; with the server spinning 2 ms a frame 164 FPS, a client frame -7.236 ms longer.

### Entities (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 125.591 | - | 3900 | 0% |
| blink | 134 | 116 | 4.199 | 603.0 | 137 | 0% |
| zap | 64 | 61 | 12.974 | 603.0 | 63 | 0% |
| zapUnchecked | 65 | 62 | 13.112 | 603.0 | 64 | 0% |
| volt | 126 | 121 | 4.946 | 603.0 | 128 | 0% |
| voltUnchecked | 133 | 126 | 3.684 | 603.0 | 134 | 0% |

Where a frame goes, in milliseconds: the fires, the flush, what the server spent receiving in a frame of its own, and the rest.

| Library | Frame | Fires | Flush | Receive | Other | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 125.591 | - | 8.048 | -66.972 | 106 | 6.031 |
| blink | 7.463 | 4.199 | 0.307 | 65.223 | -62.267 | 14 | 82.150 |
| zap | 15.625 | 12.974 | 0.186 | 60.991 | -58.526 | 15 | 30.242 |
| zapUnchecked | 15.385 | 13.112 | 0.186 | 59.514 | -57.427 | 16 | 29.709 |
| volt | 7.937 | 4.946 | 0.443 | 13.615 | -11.068 | 64 | 9.666 |
| voltUnchecked | 7.519 | 3.684 | 0.457 | 15.163 | -11.785 | 58 | 12.909 |

### Booleans (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 33.350 | - | 9800 | 0% |
| blink | 88 | 81 | 8.491 | 1003.0 | 87 | 0% |
| zap | 42 | 41 | 20.644 | 1003.0 | 42 | 0% |
| zapUnchecked | 43 | 41 | 19.873 | 1003.0 | 43 | 0% |
| volt | 142 | 135 | 4.640 | 128.0 | 144 | 0% |
| voltUnchecked | 145 | 132 | 4.679 | 128.0 | 144 | 0% |

Where a frame goes, in milliseconds: the fires, the flush, what the server spent receiving in a frame of its own, and the rest.

| Library | Frame | Fires | Flush | Receive | Other | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 33.350 | - | 7.210 | 26.106 | 128 | 0.101 |
| blink | 11.364 | 8.491 | 0.370 | 18.432 | -15.930 | 49 | 7.907 |
| zap | 23.810 | 20.644 | 0.327 | 15.359 | -12.521 | 0 | 0.029 |
| zapUnchecked | 23.256 | 19.873 | 0.330 | 15.222 | -12.169 | 14037 | 0.041 |
| volt | 7.042 | 4.640 | 0.125 | 10.794 | -8.516 | 81 | 0.441 |
| voltUnchecked | 6.897 | 4.679 | 0.124 | 10.495 | -8.402 | 84 | 0.069 |

### Snapshots (100 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 65 | 64 | 67.982 | - | 6580 | 0% |
| blink | 108 | 102 | 14.949 | 1425.6 | 109 | 0% |
| zap | 114 | 109 | 24.823 | 1425.6 | 115 | 0% |
| zapUnchecked | 109 | 107 | 26.023 | 1425.6 | 111 | 0% |
| volt | 95 | 89 | 12.487 | 1425.6 | 97 | 0% |
| voltUnchecked | 96 | 86 | 9.959 | 1425.6 | 99 | 0% |

Where a frame goes, in milliseconds: the fires, the flush, what the server spent receiving in a frame of its own, and the rest.

| Library | Frame | Fires | Flush | Receive | Other | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 15.385 | 6.798 | - | 7.975 | 0.611 | 109 | 1.350 |
| blink | 9.259 | 1.495 | 0.108 | 4.561 | 3.095 | 216 | 0.037 |
| zap | 8.772 | 2.482 | 0.116 | 4.841 | 1.332 | 189 | 0.020 |
| zapUnchecked | 9.174 | 2.602 | 0.120 | 5.463 | 0.989 | 166 | 0.026 |
| volt | 10.526 | 1.249 | 0.163 | 2.535 | 6.580 | 445 | 0.036 |
| voltUnchecked | 10.417 | 0.996 | 0.158 | 2.521 | 6.742 | 462 | 0.034 |

### Input (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 151 | 147 | 2.943 | - | 155100 | 0% |
| blink | 144 | 116 | 2.944 | 3.0 | 160900 | 0% |
| zap | 171 | 154 | 3.086 | 2.0 | 171700 | 0% |
| zapUnchecked | 182 | 157 | 2.894 | 2.0 | 180800 | 0% |
| volt | 192 | 165 | 0.407 | 3.0 | 756 | 0% |
| voltUnchecked | 166 | 145 | 0.582 | 3.0 | 676 | 0% |

Where a frame goes, in milliseconds: the fires, the flush, what the server spent receiving in a frame of its own, and the rest.

| Library | Frame | Fires | Flush | Receive | Other | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 6.623 | 2.943 | - | 7.886 | -4.207 | 111 | 1.205 |
| blink | 6.944 | 2.944 | 0.002 | 7.850 | -3.851 | 111 | 0.469 |
| zap | 5.848 | 3.086 | 0.002 | 7.854 | -5.094 | 111 | 1.637 |
| zapUnchecked | 5.495 | 2.894 | 0.001 | 7.889 | -5.289 | 112 | 1.734 |
| volt | 5.208 | 0.407 | 0.084 | 1.296 | 3.421 | 244 | 0.011 |
| voltUnchecked | 6.024 | 0.582 | 0.084 | 1.264 | 4.094 | 258 | 0.009 |

## Server & Clients, one player, second run

The same mode again on 2026-09-22 after the flattened `deliver`, with the server columns as the harness now defines them: `Other` is the client's frame less its fires and flush, `Receive per 1000` is milliseconds per thousand messages the server received, and `Server FPS` is the server's frames over the seconds of each run's receive window. Pasted from the client's Output.

Studio 0.740.0.7400927, 10 s per run, 32 payloads cycled. Idle 167 FPS; with the server spinning 2 ms a frame 171 FPS, a client frame -0.140 ms longer.

### Entities (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 130.525 | - | 4000 | 0% |
| blink | 174 | 149 | 3.444 | 603.0 | 174 | 0% |
| zap | 64 | 61 | 13.212 | 603.0 | 65 | 0% |
| zapUnchecked | 65 | 62 | 12.956 | 603.0 | 65 | 0% |
| volt | 153 | 128 | 4.225 | 603.0 | 152 | 0% |
| voltUnchecked | 174 | 151 | 3.121 | 603.0 | 173 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 130.525 | - | -63.858 | 288.537 | 112 | 2.921 |
| blink | 5.747 | 3.444 | 0.275 | 2.027 | 57.962 | 16 | 94.355 |
| zap | 15.625 | 13.212 | 0.225 | 2.188 | 49.222 | 19 | 23.059 |
| zapUnchecked | 15.385 | 12.956 | 0.225 | 2.203 | 50.714 | 19 | 24.042 |
| volt | 6.536 | 4.225 | 0.382 | 1.929 | 10.721 | 73 | 8.501 |
| voltUnchecked | 5.747 | 3.121 | 0.375 | 2.251 | 10.582 | 74 | 10.674 |

### Booleans (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 32.559 | - | 9600 | 0% |
| blink | 98 | 95 | 7.762 | 1003.0 | 97 | 0% |
| zap | 37 | 34 | 22.421 | 1003.0 | 37 | 0% |
| zapUnchecked | 38 | 37 | 22.322 | 1003.0 | 38 | 0% |
| volt | 129 | 100 | 4.892 | 128.0 | 135 | 0% |
| voltUnchecked | 134 | 126 | 5.058 | 128.0 | 135 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 32.559 | - | 34.108 | 78.385 | 144 | 0.089 |
| blink | 10.204 | 7.762 | 0.394 | 2.048 | 15.589 | 58 | 6.874 |
| zap | 27.027 | 22.421 | 0.345 | 4.261 | 16.249 | 121 | 0.050 |
| zapUnchecked | 26.316 | 22.322 | 0.347 | 3.646 | 15.997 | 125 | 0.075 |
| volt | 7.752 | 4.892 | 0.141 | 2.719 | 6.334 | 93 | 0.109 |
| voltUnchecked | 7.463 | 5.058 | 0.139 | 2.266 | 6.344 | 97 | 0.072 |

### Snapshots (100 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 64 | 62 | 68.098 | - | 6580 | 0% |
| blink | 108 | 92 | 14.937 | 1425.6 | 110 | 0% |
| zap | 115 | 104 | 25.734 | 1425.6 | 118 | 0% |
| zapUnchecked | 111 | 107 | 25.804 | 1425.6 | 113 | 0% |
| volt | 90 | 85 | 12.684 | 1425.6 | 95 | 0% |
| voltUnchecked | 97 | 88 | 9.687 | 1425.6 | 101 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 15.625 | 6.810 | - | 8.815 | 153.303 | 110 | 1.607 |
| blink | 9.259 | 1.494 | 0.111 | 7.655 | 43.591 | 162 | 0.031 |
| zap | 8.696 | 2.573 | 0.124 | 5.998 | 45.266 | 163 | 0.013 |
| zapUnchecked | 9.009 | 2.580 | 0.131 | 6.297 | 51.758 | 149 | 0.022 |
| volt | 11.111 | 1.268 | 0.174 | 9.669 | 25.795 | 180 | 0.018 |
| voltUnchecked | 10.309 | 0.969 | 0.161 | 9.179 | 23.484 | 188 | 0.041 |

### Input (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 160 | 144 | 2.855 | - | 158800 | 0% |
| blink | 147 | 139 | 3.085 | 3.0 | 149200 | 0% |
| zap | 147 | 143 | 3.343 | 2.0 | 148800 | 0% |
| zapUnchecked | 153 | 131 | 3.106 | 2.0 | 157200 | 0% |
| volt | 176 | 158 | 0.366 | 3.0 | 708 | 0% |
| voltUnchecked | 158 | 147 | 0.624 | 3.0 | 653 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 6.250 | 2.855 | - | 3.395 | 6.373 | 110 | 1.609 |
| blink | 6.803 | 3.085 | 0.002 | 3.716 | 7.071 | 109 | 2.260 |
| zap | 6.803 | 3.343 | 0.002 | 3.458 | 6.714 | 110 | 1.619 |
| zapUnchecked | 6.536 | 3.106 | 0.002 | 3.428 | 6.261 | 110 | 1.363 |
| volt | 5.682 | 0.366 | 0.076 | 5.240 | 0.916 | 205 | 0.021 |
| voltUnchecked | 6.329 | 0.624 | 0.086 | 5.619 | 0.965 | 190 | 0.008 |

## Server & Clients, one player, the server at sixty

The same mode on 2026-09-22 with the server's Heartbeat spun out to a sixtieth of a second from where its last spin ended, so every library's server steps no faster than a live one. Pasted from the client's Output.

Studio 0.740.0.7400927, 10 s per run, 32 payloads cycled.

### Entities (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 131.005 | - | 4000 | 0% |
| blink | 160 | 107 | 3.686 | 603.0 | 153 | 0% |
| zap | 61 | 56 | 13.754 | 603.0 | 60 | 0% |
| zapUnchecked | 60 | 58 | 13.719 | 603.0 | 60 | 0% |
| volt | 128 | 121 | 4.746 | 603.0 | 129 | 0% |
| voltUnchecked | 127 | 113 | 3.382 | 603.0 | 128 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 131.005 | - | -64.338 | 349.041 | 59 | 18.915 |
| blink | 6.250 | 3.686 | 0.354 | 2.209 | 58.343 | 16 | 82.236 |
| zap | 16.393 | 13.754 | 0.290 | 2.349 | 57.998 | 16 | 26.289 |
| zapUnchecked | 16.667 | 13.719 | 0.285 | 2.663 | 56.557 | 17 | 25.641 |
| volt | 7.812 | 4.746 | 0.464 | 2.603 | 13.698 | 54 | 13.500 |
| voltUnchecked | 7.874 | 3.382 | 0.476 | 4.016 | 14.304 | 53 | 13.857 |

### Booleans (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 35.301 | - | 9400 | 0% |
| blink | 86 | 78 | 8.727 | 1003.0 | 85 | 0% |
| zap | 40 | 39 | 22.160 | 1003.0 | 40 | 0% |
| zapUnchecked | 40 | 38 | 21.971 | 1003.0 | 40 | 0% |
| volt | 131 | 108 | 4.857 | 128.0 | 129 | 0% |
| voltUnchecked | 137 | 128 | 4.590 | 128.0 | 140 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 35.301 | - | 31.365 | 94.846 | 60 | 8.784 |
| blink | 11.628 | 8.727 | 0.382 | 2.518 | 18.103 | 48 | 7.477 |
| zap | 25.000 | 22.160 | 0.373 | 2.468 | 15.734 | 57 | 0.095 |
| zapUnchecked | 25.000 | 21.971 | 0.371 | 2.658 | 15.194 | 58 | 0.062 |
| volt | 7.634 | 4.857 | 0.150 | 2.627 | 7.319 | 59 | 4.265 |
| voltUnchecked | 7.299 | 4.590 | 0.135 | 2.575 | 6.823 | 59 | 4.571 |

### Snapshots (100 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 71 | 69 | 62.718 | - | 7150 | 0% |
| blink | 125 | 112 | 11.827 | 1425.6 | 127 | 0% |
| zap | 130 | 127 | 19.177 | 1425.6 | 132 | 0% |
| zapUnchecked | 130 | 119 | 19.600 | 1425.6 | 129 | 0% |
| volt | 117 | 105 | 8.649 | 1425.6 | 120 | 0% |
| voltUnchecked | 128 | 114 | 6.466 | 1425.6 | 127 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 14.085 | 6.272 | - | 7.813 | 163.976 | 60 | 14.666 |
| blink | 8.000 | 1.183 | 0.114 | 6.703 | 38.899 | 59 | 0.046 |
| zap | 7.692 | 1.918 | 0.122 | 5.652 | 41.003 | 59 | 0.030 |
| zapUnchecked | 7.692 | 1.960 | 0.127 | 5.605 | 45.247 | 59 | 0.087 |
| volt | 8.547 | 0.865 | 0.179 | 7.503 | 21.956 | 60 | 0.051 |
| voltUnchecked | 7.812 | 0.647 | 0.159 | 7.007 | 21.847 | 59 | 0.027 |

### Input (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 148 | 141 | 2.836 | - | 148900 | 0% |
| blink | 149 | 136 | 2.830 | 3.0 | 148700 | 0% |
| zap | 144 | 133 | 3.191 | 2.0 | 144800 | 0% |
| zapUnchecked | 146 | 139 | 3.044 | 2.0 | 148200 | 0% |
| volt | 137 | 128 | 0.274 | 3.0 | 553 | 0% |
| voltUnchecked | 132 | 123 | 0.371 | 3.0 | 546 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 6.757 | 2.836 | - | 3.920 | 6.747 | 60 | 11.324 |
| blink | 6.711 | 2.830 | 0.002 | 3.880 | 7.151 | 59 | 12.501 |
| zap | 6.944 | 3.191 | 0.002 | 3.752 | 7.083 | 59 | 11.746 |
| zapUnchecked | 6.849 | 3.044 | 0.002 | 3.803 | 6.882 | 59 | 11.636 |
| volt | 7.299 | 0.274 | 0.060 | 6.966 | 0.720 | 60 | 0.041 |
| voltUnchecked | 7.576 | 0.371 | 0.057 | 7.148 | 0.726 | 60 | 0.035 |

## Server & Clients, one player, Studio 0.745

The same mode on 2026-10-28, on the build branch with `onHandshake` after the releasing flush and M6 staged, nothing else open. Taken from the report `lune run bench` captured into `Results.md`, which the run's Studio printed.

Studio 0.745.0.7451137, 10 s per run, 32 payloads cycled.

### Entities (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 94.087 | - | 6200 | 0% |
| blink | 178 | 163 | 3.505 | 603.0 | 174 | 0% |
| zap | 64 | 60 | 12.747 | 603.0 | 64 | 0% |
| zapUnchecked | 60 | 56 | 13.996 | 603.0 | 59 | 0% |
| volt | 131 | 111 | 4.828 | 603.0 | 129 | 0% |
| voltUnchecked | 160 | 150 | 3.348 | 603.0 | 160 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 94.087 | - | -27.420 | 197.869 | 59 | 15.634 |
| blink | 5.618 | 3.505 | 0.515 | 1.598 | 29.835 | 31 | 46.061 |
| zap | 15.625 | 12.747 | 0.450 | 2.428 | 34.981 | 26 | 14.434 |
| zapUnchecked | 16.667 | 13.996 | 0.476 | 2.194 | 36.963 | 25 | 13.752 |
| volt | 7.634 | 4.828 | 0.603 | 2.203 | 11.280 | 59 | 11.793 |
| voltUnchecked | 6.250 | 3.348 | 0.602 | 2.300 | 11.467 | 58 | 17.239 |

### Booleans (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 62.436 | - | 7200 | 0% |
| blink | 84 | 75 | 8.911 | 1003.0 | 83 | 0% |
| zap | 41 | 40 | 21.363 | 1003.0 | 40 | 0% |
| zapUnchecked | 39 | 37 | 21.686 | 1003.0 | 40 | 0% |
| volt | 178 | 177 | 3.850 | 128.0 | 178 | 0% |
| voltUnchecked | 174 | 166 | 3.987 | 128.0 | 173 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 62.436 | - | 4.230 | 136.957 | 60 | 10.618 |
| blink | 11.905 | 8.911 | 0.655 | 2.340 | 14.987 | 55 | 5.011 |
| zap | 24.390 | 21.363 | 0.593 | 2.435 | 17.134 | 51 | 0.059 |
| zapUnchecked | 25.641 | 21.686 | 0.611 | 3.344 | 14.663 | 57 | 0.054 |
| volt | 5.618 | 3.850 | 0.142 | 1.625 | 4.717 | 59 | 4.572 |
| voltUnchecked | 5.747 | 3.987 | 0.144 | 1.617 | 4.799 | 59 | 4.388 |

### Snapshots (100 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 73 | 66 | 60.923 | - | 7310 | 0% |
| blink | 209 | 200 | 12.460 | 1425.6 | 215 | 0% |
| zap | 188 | 171 | 20.836 | 1425.6 | 188 | 0% |
| zapUnchecked | 208 | 179 | 18.478 | 1425.6 | 207 | 0% |
| volt | 213 | 199 | 6.253 | 1425.6 | 217 | 0% |
| voltUnchecked | 223 | 210 | 5.476 | 1425.6 | 225 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 13.699 | 6.092 | - | 7.606 | 122.184 | 60 | 8.769 |
| blink | 4.785 | 1.246 | 0.158 | 3.380 | 28.703 | 59 | 1.668 |
| zap | 5.319 | 2.084 | 0.225 | 3.011 | 34.781 | 59 | 1.810 |
| zapUnchecked | 4.808 | 1.848 | 0.192 | 2.768 | 33.488 | 59 | 2.631 |
| volt | 4.695 | 0.625 | 0.192 | 3.877 | 18.713 | 60 | 0.031 |
| voltUnchecked | 4.484 | 0.548 | 0.193 | 3.743 | 18.164 | 60 | 0.031 |

### Input (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 164 | 137 | 2.935 | - | 160700 | 0% |
| blink | 162 | 125 | 3.294 | 3.0 | 156100 | 0% |
| zap | 165 | 153 | 3.296 | 2.0 | 164200 | 0% |
| zapUnchecked | 178 | 158 | 3.091 | 2.0 | 175100 | 0% |
| volt | 234 | 224 | 0.209 | 3.0 | 936 | 0% |
| voltUnchecked | 213 | 187 | 0.326 | 3.0 | 843 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 6.098 | 2.935 | - | 3.162 | 5.947 | 60 | 10.056 |
| blink | 6.173 | 3.294 | 0.002 | 2.877 | 6.520 | 59 | 11.490 |
| zap | 6.061 | 3.296 | 0.002 | 2.763 | 5.833 | 59 | 10.214 |
| zapUnchecked | 5.618 | 3.091 | 0.002 | 2.525 | 5.127 | 60 | 8.905 |
| volt | 4.274 | 0.209 | 0.049 | 4.015 | 0.512 | 59 | 0.033 |
| voltUnchecked | 4.695 | 0.326 | 0.058 | 4.310 | 0.617 | 59 | 0.033 |

## Server & Clients, one player, Studio 0.745, second run

A repeat of the run above on 2026-10-28, on the same code, pasted from the client's Output.

Studio 0.745.0.7451137, 10 s per run, 32 payloads cycled.

### Entities (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 91.821 | - | 6300 | 0% |
| blink | 173 | 166 | 3.563 | 603.0 | 174 | 0% |
| zap | 61 | 53 | 14.104 | 603.0 | 58 | 0% |
| zapUnchecked | 51 | 49 | 16.034 | 603.0 | 52 | 0% |
| volt | 116 | 101 | 5.371 | 603.0 | 116 | 0% |
| voltUnchecked | 160 | 144 | 3.419 | 603.0 | 157 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 91.821 | - | -25.155 | 189.426 | 59 | 14.923 |
| blink | 5.780 | 3.563 | 0.393 | 1.824 | 32.932 | 28 | 51.982 |
| zap | 16.393 | 14.104 | 0.393 | 1.897 | 39.173 | 23 | 14.838 |
| zapUnchecked | 19.608 | 16.034 | 0.431 | 3.143 | 41.364 | 22 | 13.420 |
| volt | 8.621 | 5.371 | 0.684 | 2.565 | 11.781 | 58 | 9.829 |
| voltUnchecked | 6.250 | 3.419 | 0.644 | 2.187 | 11.618 | 59 | 16.747 |

### Booleans (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 64.984 | - | 6900 | 0% |
| blink | 81 | 74 | 9.191 | 1003.0 | 80 | 0% |
| zap | 36 | 34 | 24.093 | 1003.0 | 36 | 0% |
| zapUnchecked | 38 | 34 | 22.768 | 1003.0 | 38 | 0% |
| volt | 176 | 152 | 3.919 | 128.0 | 173 | 0% |
| voltUnchecked | 165 | 133 | 4.238 | 128.0 | 160 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 64.984 | - | 1.683 | 147.435 | 59 | 11.253 |
| blink | 12.346 | 9.191 | 0.695 | 2.460 | 16.162 | 51 | 5.580 |
| zap | 27.778 | 24.093 | 0.655 | 3.030 | 15.951 | 54 | 0.047 |
| zapUnchecked | 26.316 | 22.768 | 0.623 | 2.924 | 15.155 | 56 | 0.054 |
| volt | 5.682 | 3.919 | 0.146 | 1.616 | 4.852 | 59 | 4.456 |
| voltUnchecked | 6.061 | 4.238 | 0.151 | 1.671 | 5.157 | 59 | 3.591 |

### Snapshots (100 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 70 | 60 | 66.156 | - | 6860 | 0% |
| blink | 183 | 169 | 13.876 | 1425.6 | 187 | 0% |
| zap | 186 | 170 | 20.596 | 1425.6 | 188 | 0% |
| zapUnchecked | 188 | 129 | 20.715 | 1425.6 | 177 | 0% |
| volt | 215 | 196 | 6.747 | 1425.6 | 211 | 0% |
| voltUnchecked | 207 | 200 | 5.716 | 1425.6 | 210 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 14.286 | 6.616 | - | 7.670 | 132.824 | 59 | 9.118 |
| blink | 5.464 | 1.388 | 0.181 | 3.896 | 32.512 | 59 | 1.266 |
| zap | 5.376 | 2.060 | 0.193 | 3.124 | 34.409 | 59 | 1.590 |
| zapUnchecked | 5.319 | 2.071 | 0.223 | 3.025 | 41.288 | 59 | 3.245 |
| volt | 4.651 | 0.675 | 0.176 | 3.800 | 19.032 | 59 | 0.034 |
| voltUnchecked | 4.831 | 0.572 | 0.174 | 4.086 | 19.289 | 59 | 0.034 |

### Input (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 177 | 168 | 2.706 | - | 176400 | 0% |
| blink | 172 | 136 | 3.151 | 3.0 | 164800 | 0% |
| zap | 168 | 136 | 3.290 | 2.0 | 163100 | 0% |
| zapUnchecked | 163 | 130 | 3.307 | 2.0 | 161400 | 0% |
| volt | 232 | 222 | 0.238 | 3.0 | 923 | 0% |
| voltUnchecked | 203 | 183 | 0.354 | 3.0 | 823 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 5.650 | 2.706 | - | 2.944 | 5.833 | 60 | 11.603 |
| blink | 5.814 | 3.151 | 0.002 | 2.662 | 6.170 | 59 | 11.560 |
| zap | 5.952 | 3.290 | 0.002 | 2.660 | 5.760 | 60 | 9.848 |
| zapUnchecked | 6.135 | 3.307 | 0.002 | 2.826 | 6.139 | 59 | 10.770 |
| volt | 4.310 | 0.238 | 0.054 | 4.018 | 0.588 | 60 | 0.036 |
| voltUnchecked | 4.926 | 0.354 | 0.059 | 4.513 | 0.696 | 59 | 0.029 |

## Server & Clients, one player, Studio 0.745, on 17.B

The same mode on 2026-10-29, on `main` at `f4cfabd` with 17.B merged, nothing else open; its generated modules and runtime are byte-identical to the two runs above. Taken from the report `lune run bench` captured into `Results.md`, which the run's Studio printed.

Studio 0.745.0.7451137, 10 s per run, 32 payloads cycled.

### Entities (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 96.578 | - | 5800 | 0% |
| blink | 196 | 187 | 3.053 | 603.0 | 195 | 0% |
| zap | 70 | 65 | 11.760 | 603.0 | 70 | 0% |
| zapUnchecked | 64 | 62 | 12.615 | 603.0 | 65 | 0% |
| volt | 155 | 147 | 3.852 | 603.0 | 160 | 0% |
| voltUnchecked | 172 | 154 | 3.063 | 603.0 | 171 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 96.578 | - | -29.911 | 198.536 | 59 | 14.127 |
| blink | 5.102 | 3.053 | 0.358 | 1.691 | 26.995 | 34 | 46.807 |
| zap | 14.286 | 11.760 | 0.324 | 2.201 | 29.859 | 31 | 12.703 |
| zapUnchecked | 15.625 | 12.615 | 0.409 | 2.601 | 30.759 | 30 | 11.839 |
| volt | 6.452 | 3.852 | 0.609 | 1.990 | 9.186 | 59 | 16.499 |
| voltUnchecked | 5.814 | 3.063 | 0.634 | 2.117 | 11.278 | 59 | 18.934 |

### Booleans (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 72.969 | - | 6300 | 0% |
| blink | 77 | 72 | 9.474 | 1003.0 | 77 | 0% |
| zap | 41 | 41 | 20.786 | 1003.0 | 42 | 0% |
| zapUnchecked | 39 | 37 | 21.698 | 1003.0 | 40 | 0% |
| volt | 194 | 180 | 3.506 | 128.0 | 193 | 0% |
| voltUnchecked | 165 | 157 | 4.190 | 128.0 | 165 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 66.667 | 72.969 | - | -6.302 | 148.181 | 59 | 9.324 |
| blink | 12.987 | 9.474 | 0.787 | 2.726 | 16.592 | 50 | 5.323 |
| zap | 24.390 | 20.786 | 0.596 | 3.008 | 14.607 | 58 | 0.082 |
| zapUnchecked | 25.641 | 21.698 | 0.610 | 3.332 | 14.638 | 57 | 0.071 |
| volt | 5.155 | 3.506 | 0.131 | 1.518 | 4.422 | 59 | 5.239 |
| voltUnchecked | 6.061 | 4.190 | 0.151 | 1.720 | 5.094 | 59 | 3.805 |

### Snapshots (100 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 76 | 73 | 58.735 | - | 7620 | 0% |
| blink | 204 | 185 | 11.804 | 1425.6 | 205 | 0% |
| zap | 183 | 171 | 20.410 | 1425.6 | 184 | 0% |
| zapUnchecked | 206 | 197 | 18.219 | 1425.6 | 209 | 0% |
| volt | 209 | 199 | 6.733 | 1425.6 | 207 | 0% |
| voltUnchecked | 200 | 191 | 5.604 | 1425.6 | 204 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 13.158 | 5.873 | - | 7.284 | 112.746 | 60 | 7.984 |
| blink | 4.902 | 1.180 | 0.158 | 3.564 | 28.398 | 59 | 1.006 |
| zap | 5.464 | 2.041 | 0.193 | 3.230 | 34.595 | 59 | 1.662 |
| zapUnchecked | 4.854 | 1.822 | 0.168 | 2.864 | 34.443 | 59 | 3.081 |
| volt | 4.785 | 0.673 | 0.174 | 3.938 | 19.078 | 60 | 0.035 |
| voltUnchecked | 5.000 | 0.560 | 0.173 | 4.266 | 19.418 | 60 | 0.035 |

### Input (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 171 | 161 | 2.824 | - | 170300 | 0% |
| blink | 187 | 153 | 2.878 | 3.0 | 181700 | 0% |
| zap | 186 | 171 | 2.913 | 2.0 | 184700 | 0% |
| zapUnchecked | 173 | 159 | 3.108 | 2.0 | 172300 | 0% |
| volt | 229 | 220 | 0.214 | 3.0 | 926 | 0% |
| voltUnchecked | 213 | 194 | 0.293 | 3.0 | 858 | 0% |

Where a client frame goes, in milliseconds, then the server on its own frame, stepped no faster than a live server: what a thousand messages cost it to receive, its frame rate while they arrived, and how far behind it was when the fires stopped.

| Library | Frame | Fires | Flush | Other | Receive per 1000 | Server FPS | Lag s |
|---|---|---|---|---|---|---|---|
| roblox | 5.848 | 2.824 | - | 3.024 | 5.889 | 60 | 11.033 |
| blink | 5.348 | 2.878 | 0.002 | 2.468 | 5.778 | 59 | 12.017 |
| zap | 5.376 | 2.913 | 0.002 | 2.462 | 5.354 | 60 | 10.750 |
| zapUnchecked | 5.780 | 3.108 | 0.002 | 2.671 | 5.337 | 60 | 9.349 |
| volt | 4.367 | 0.214 | 0.052 | 4.101 | 0.515 | 60 | 0.032 |
| voltUnchecked | 4.695 | 0.293 | 0.051 | 4.350 | 0.531 | 59 | 0.030 |

