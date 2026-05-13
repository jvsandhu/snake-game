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

## Features

**Wrap mode** — toggle with `O`. Snake exits one side and enters the
other. No wall deaths — the only way to die is to eat yourself.

**Ramp mode** — toggle with `I`. Speed increases as your score goes
up. Starts at 160ms per tick, caps at 50ms.

**High score** — persisted to `snake.hs` in the same directory as the
executable. Survives restarts.

**Input buffering** — up to 2 direction changes are queued per tick.
Fast taps never get lost, even during a single tick.

**Tail gradient** — head is bright green, body smoothly fades to
dark green toward the tail.

**Double buffering** — all rendering happens off-screen, then blits
to the window in one shot. Zero flicker.

**Death reason** — the game over screen tells you whether you hit
a wall or ate yourself.

**Death flash** — brief red flash on death for visual feedback.

**Playfield border** — white outline around the grid.

**Window centering** — automatically centered on screen at launch.

## Specs

```
Grid:          20 x 20
Cell:          28 px
Base tick:     160 ms
Render tick:   16 ms (60 FPS)
High score:    persisted to snake.hs
Window:        fixed-size, centered, GUI subsystem
Binary:        ~34 KB (ReleaseSmall)
```

## Why

Dependencies are overrated.
