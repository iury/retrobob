# retrobob

retrobob is a retro gaming emulator that runs directly on your browser.

## Links

[Live demo](https://retrobob.bitzero.com.br/)

## Building

You'll need [pnpm](https://pnpm.io/installation), [zig 0.12](https://ziglang.org/download/),
and [emscripten](https://emscripten.org/docs/getting_started/downloads.html)
installed and active. Then, it is as simple as:

    pnpm install
    cd packages/ui
    pnpm dev

You can also run the emulator directly as a native executable, without the browser:

    cd packages/engine
    zig build run -Doptimize=ReleaseFast

## Controls

A gamepad (Xbox/PS) or keyboard:

| Action          |        Key |
| --------------- | ---------: |
| Fullscreen      |        F11 |
| Save state      |         F1 |
| Load state      |         F4 |
| Reset           |         F3 |
| Pause / resume  |      Space |
| D-pad           | Arrow keys |
| Select          |          Q |
| Start           | W or Enter |
| _NES / Famicom_ |            |
| B               |     Z or A |
| A               |     X or S |

## Supported Systems

### NES / Famicom

Only the main mappers are implemented but most commercial games should work.

#### Known Issues

- Castlevania 3 (MMC5 mapper is not implemented)
- Batman: Return of the Joker (FME-7 mapper is not implemented)
- Battletoads and BT&DD (random crashes)

## News

### 2024-02-17 - Now using WebAssembly

[Zig](https://ziglang.org/) is back. Now using the power of WebAssembly!

All rendering and input are handled by the [emscripten](https://emscripten.org/) and [raylib](https://www.raylib.com/) library.
Now you can save and load your game state, play using a gamepad, change the aspect ratio, and change the console region to NTSC or PAL.

There were heavy synchronization issues to tackle. The audio part was done from scratch to take advantage of AudioWorklets.
You can occasionally hear some artifacts, but these are due of the main thread needing to rely on setTimeout to do the frame ticking.
Since it is not highly accurate, it will get eventually out of sync with the audio thread.

Battletoads will crash on the second stage. It is very hard to emulate it correctly since it needs a lot of timing precision.
I may eventually try again to make it run, but I prefer to do an emulator of another system for now.

### 2024-02-02 - First version is out!

This version is a port of an earlier build that I made using [Zig](https://ziglang.org/). I was playing with some options for a new version,
such as to use [Rust](https://www.rust-lang.org/), but in the end I took the challenge of writing an emulator entirely in pure JavaScript.
This is the result of it.

It has an implementation of the NES Audio Processing Unit, but at very late in the development I discovered that it is really hard to
sync audio samples between a Web Worker and the main thread at 60 FPS, and to write them all in pure JS. So, it's unlikely that you'll
be able to run it at 60 FPS with audio output enabled. Also, the implementation of the triangle wave seems to be faulty.

All the major mappers are implemented: NROM, CNROM, UxROM, AxROM, MMC1, MMC2 and MMC3. There are some games with graphical glitches and
Battletoads will crash in the second level. Probably the sprite 0 hit detection has some bugs and I am missing some memory readings for
the MMC2/MMC3 to do their thing.

[NesDev Wiki](https://www.nesdev.org/wiki/Nesdev_Wiki) was the main resource about the NES internals. I also recommend
[this site](https://www.masswerk.at/6502/6502_instruction_set.html) for how to do a 6502 CPU implementation. A lot of the PPU and
pretty much the entire APU was ported from the [Mesen](https://github.com/SourMesen/Mesen) source code. I also rebuild the
[blip-buf](https://code.google.com/archive/p/blip-buf/) library entirely in JavaScript.

I intend to build the next version using WebAssembly so it can run with audio at 60 FPS, to add support for gamepads and to add more
systems in the future. This version will be tagged as an archive for anyone who is curious about a 100% implementation using JavaScript only.
