# Volt benchmark

Run 2026-09-22 with zap 0.6.29, blink 0.18.9, volt 0.1.0.
Studio 0.739.0.7390687, 10 s per run, 32 payloads cycled.

## Entities (400 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 124.162 | - | 4200 | 0% |
| blink | 147 | 122 | 4.034 | 603.0 | 154 | 0% |
| zap | 135 | 117 | 12.987 | 603.0 | 136 | 0% |
| zapUnchecked | 155 | 123 | 12.240 | 603.0 | 150 | 0% |
| volt | 106 | 96 | 16.793 | 603.0 | 106 | 0% |
| voltUnchecked | 183 | 131 | 3.138 | 603.0 | 177 | 0% |

## Booleans (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 15 | 15 | 41.353 | - | 9800 | 0% |
| blink | 89 | 81 | 8.174 | 1003.0 | 90 | 0% |
| zap | 41 | 38 | 21.234 | 1003.0 | 41 | 0% |
| zapUnchecked | 40 | 36 | 21.382 | 1003.0 | 40 | 0% |
| volt | 55 | 53 | 16.180 | 128.0 | 55 | 0% |
| voltUnchecked | 55 | 54 | 16.214 | 128.0 | 55 | 0% |

## Snapshots (100 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 73 | 68 | 64.052 | - | 7370 | 0% |
| blink | 104 | 94 | 14.860 | 1425.6 | 107 | 0% |
| zap | 179 | 111 | 18.722 | 1425.6 | 166 | 0% |
| zapUnchecked | 113 | 106 | 21.843 | 1425.6 | 116 | 0% |
| volt | 97 | 91 | 29.134 | 1425.6 | 105 | 0% |
| voltUnchecked | 108 | 85 | 20.651 | 1425.6 | 111 | 0% |

## Input (1000 fires a frame)

| Library | FPS median | FPS min | ms per 1000 fires | Bytes per message | Packets per second | Loss |
|---|---|---|---|---|---|---|
| roblox | 174 | 133 | 2.669 | - | 170700 | 0% |
| blink | 184 | 163 | 2.724 | 3.0 | 181200 | 0% |
| zap | 178 | 173 | 2.877 | 2.0 | 178300 | 0% |
| zapUnchecked | 181 | 171 | 2.834 | 2.0 | 181000 | 0% |
| volt | 175 | 161 | 0.475 | 3.0 | 708 | 0% |
| voltUnchecked | 168 | 155 | 0.461 | 3.0 | 678 | 0% |
C:\Users\Michael\OneDrive\Desktop\Game Development\Volt\tools/bench:117: Studio printed no report
[Stack Begin]
    Script '[C]' - function 'assert'
    Script 'C:\Users\Michael\OneDrive\Desktop\Game Development\Volt\tools/bench', Line 117
[Stack End]

bench exit 1

## Generated modules

| Library | Client | Server |
|---|---|---|
| Blink | 10.6 KB, 389 lines | 14.6 KB, 492 lines |
| Zap | 8.7 KB, 318 lines | 10.1 KB, 377 lines |
| ZapUnchecked | 8.4 KB, 310 lines | 10.2 KB, 377 lines |
| Volt | 9.4 KB, 330 lines | 7.8 KB, 295 lines |
| VoltUnchecked | 6.3 KB, 227 lines | 7.9 KB, 295 lines |
