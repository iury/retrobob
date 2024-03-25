# Overview

**retrobob** is a retro gaming emulator made by [iury](https://x.com/iury) that runs directly on your browser.

Super Nintendo, NES/Famicom, Gameboy and Gameboy Color are currently supported, with more systems to come.

You can also [download](https://github.com/iury/retrobob/releases) it as a native executable for stable FPS and better audio quality.

Don't have a ROM to test it? Try [Super Tilt Bro](https://sgadrat.itch.io/super-tilt-bro), a free game made by sgadrat.

## Links

[Live demo](https://retrobob.bitzero.com.br/)

### Warning

You'll most likely lose your savestates after version releases. So, if you are playing for real then I recommend
[downloading](https://github.com/iury/retrobob/releases) the executable and saving locally. As we're under active
development, no compatibility is guaranteed between different versions.

## Compiling

You'll need [pnpm](https://pnpm.io/installation), [zig 0.12](https://ziglang.org/download/),
and [emscripten](https://emscripten.org/docs/getting_started/downloads.html) installed,
active and with the cache generated (compile a hello world using emcc).
Then, it is as simple as:

    git submodule update --init --recursive
    pnpm install
    cd packages/ui
    pnpm dev

You can also run the emulator directly as a native executable, without the browser:

    cd packages/engine
    zig build run --release=fast

## Controls

A gamepad (Xbox/PS) or keyboard:

| System                     |        Action         | Key        |
| -------------------------- | :-------------------: | ---------- |
| Global                     |                       |            |
|                            |      Fullscreen       | F11        |
|                            |      Save state       | F1         |
|                            |      Load state       | F4         |
|                            |         Reset         | F3         |
|                            |    Pause / resume     | Space      |
|                            |         D-pad         | Arrow keys |
|                            |        Select         | Q          |
|                            |         Start         | W or Enter |
| _Super Nintendo_           |                       |
|                            |           Y           | A          |
|                            |           X           | S          |
|                            |           B           | Z          |
|                            |           A           | X          |
|                            |           L           | D          |
|                            |           R           | C          |
| _NES / Famicom / GB / GBC_ |                       |
|                            |           B           | Z or A     |
|                            |           A           | X or S     |
| _Gameboy (monochrome)_     |                       |
|                            | Toggle color palettes | T          |

## Supported Systems

### SNES

- Most commercial games are playable if they don't [require a coprocessor](https://en.wikipedia.org/wiki/List_of_Super_NES_enhancement_chips#List_of_Super_NES_games_with_enhancement_chips).
- All background modes are implemented, including Mode 7 (+ExtBG).
- NTSC/PAL, 224p/239p + interlacing, pseudo hires (SETINI) and true hires (mode 5/6) are supported.
- Offset per tile (on mode 2, 4 and 6) is implemented.
- All PPU features, including mosaic, color windows and color math are implemented.

#### Known Issues

- You may experience random glitches and crashes due to emulation inaccuracies.
- A few games are unplayable, notably all Donkey Kong Country games and various Square and Enix JRPGs.

### GB / GBC

- Most commercial games should work.
- MBCs implemented: ROM, MBC1, MBC2, MBC3 (+RTC) and MBC5.
- Games in monochrome will use a color palette like playing on a GBC hardware by default but you can toggle it by pressing T.

#### Known Issues

- Super Mario Bros. Deluxe (slowdowns and glitches)

### NES / Famicom

- Most commercial games should work.
- Mappers implemented: NROM, CNROM, UxROM, AxROM, MMC1, MMC2 and MMC3.

#### Known Issues

- Castlevania 3 (MMC5 mapper is not implemented)
- Batman: Return of the Joker (FME-7 mapper is not implemented)
- Battletoads and BT&DD (random crashes)
