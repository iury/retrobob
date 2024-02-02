# retrobob

retrobob is a retro gaming emulator that runs directly on your browser.

## Links

[Live demo](https://retrobob.bitzero.com.br/)

## Supported Systems

### NES / Famicom

Only the main mappers are implemented but most commercial games should work.

#### Controls

| Action         | Key        |
| -------------- | ---------- |
| Reset          | F3         |
| Pause / Resume | Space      |
| D-pad          | Arrow keys |
| Start          | Q          |
| Select         | W          |
| B              | Z or A     |
| A              | X or S     |

#### Known Issues

- Castlevania 3 (MMC5 mapper is not implemented)
- Super Mario Bros. 3 (graphical glitches)
- Punch-out!! (graphical glitches)
- Battletoads (crashes)
- Battletoads & Double Dragon (unplayable)

## News

### 2024-02-02 - First version is out!

Hello!

This version is a port of an earlier build that I made using [Zig](https://ziglang.org/). I was playing with some options for a new version, such as to use [Rust](https://www.rust-lang.org/), but in the end I took the challenge of writing an emulator entirely in pure JavaScript. This is the result of it.

It has an implementation of the NES Audio Processing Unit, but at very late in the development I discovered that it is really hard to sync audio samples between a Web Worker and the main thread at 60 FPS, and to write them all in pure JS. So, it's unlikely that you'll be able to run it at 60 FPS with audio output enabled. Also, the implementation of the triangle wave seems to be faulty.

All the major mappers are implemented: NROM, CNROM, UxROM, AxROM, MMC1, MMC2 and MMC3. There are some games with graphical glitches and Battletoads will crash in the second level. Probably the sprite 0 hit detection has some bugs and I am missing some memory readings for the MMC2/MMC3 to do their thing.

[NesDev Wiki](https://www.nesdev.org/) was the main resource about the NES internals. I also recommend [this site](https://www.masswerk.at/6502/6502_instruction_set.html) for how to do a 6502 CPU implementation. A lot of the PPU and pretty much the entire APU was ported from the [Mesen](https://github.com/SourMesen/Mesen) source code. I also rebuild the [blip-buf](https://code.google.com/archive/p/blip-buf/) library entirely in JavaScript.

I intend to build the next version using WebAssembly so it can run with audio at 60 FPS, to add support for Gamepads and to add more systems in the future. This version will be tagged as an archive for anyone who is curious about a 100% implementation using JavaScript only.
