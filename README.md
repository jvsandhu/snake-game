# Snake

Classic Snake game written in [Zig](https://ziglang.org/), using the Win32 API directly — zero external dependencies, no game libraries.

## How to Build

**On Windows (native):**

```sh
zig build
```

**Cross-compile from Linux/macOS:**

```sh
zig build -Dtarget=x86_64-windows
```

The output is a single `snake.exe` — no DLLs, no runtime, no nothing. Just run it.

## Download

Pre-built binaries are available on the [Releases page](https://github.com/jvsandhu/snake-game/releases).

## How to Play

| Key           | Action                    |
|---------------|---------------------------|
| WASD / Arrows | Move the snake            |
| P             | Toggle pause              |
| O             | Toggle wrap-around walls  |
| I             | Toggle difficulty ramp    |
| R / Space     | Restart on game over      |

Eat food, grow longer, don't hit walls or yourself.

**Wrap mode** — snake exits one side and enters the other (no wall deaths).  
**Ramp mode** — speed increases as your score goes up (starts at 160ms, caps at 50ms per tick).

## Specs

```
Grid:          20 x 20
Cell:          28 px
Base tick:     160 ms
Render tick:   16 ms (60 FPS)
High score:    tracked per session
Window:        fixed-size, GUI subsystem
Binary:        ~34 KB (ReleaseSmall)
```

## Why

Dependencies are overrated.
