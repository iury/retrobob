## News

### 2024-03-25 - SNES support

Support for the Super Nintendo was added.

A dream comes true. I was fascinated by emulators since the good old [ZSNES](https://en.wikipedia.org/wiki/ZSNES) way back
in the very early '00s. As a kid, I really wanted to know so much about programming that one day I'd be able to code
my very own SNES emulator. Well, the time has come!

Surprisingly, I didn't find a site as good as Pan Docs for the SNES. There is [this](https://problemkaputt.de/fullsnes.htm)
very thorough and highly technical document, and [some](https://snes.nesdev.org/wiki/SNESdev_Wiki/)
[wikis](https://wiki.superfamicom.org/) that did help. But what helped most were [these](https://github.com/PeterLemon/SNES)
test ROMs.

For the CPU, I recommend [this site](http://www.6502.org/tutorials/65c816opcodes.html) and you'll definitely should
check [this page](http://www.6502.org/tutorials/decimal_mode.html#A) as well. Also, you can use
[this](https://github.com/TomHarte/ProcessorTests/tree/main/65816) to test your implementation.

But overall, the SNES was indeed quite a challenge. Most games are playable, but glitches may appear here and there.
Accurate cycle timing is a nightmare with all that thing about the clock depending on memory region. Also, I'm not an audio expert
(nor a novice, as a matter of fact), so the DSP (not the SPC700) code is heavenly borrowed from [Mesen](https://github.com/SourMesen/Mesen).

### 2024-02-27 - GB/GBC support

Support for the Gameboy and Gameboy Color was added. MBCs implemented: ROM, MBC1, MBC2, MBC3 and MBC5.

[GBDev Pan Docs](https://gbdev.io/pandocs/About.html) was the main source of information.
For the CPU, I recommend [this site](https://rgbds.gbdev.io/docs/v0.7.0/gbz80.7) and
[this handy little table](https://gb-archive.github.io/salvage/decoding_gbz80_opcodes/Decoding%20Gamboy%20Z80%20Opcodes.html).

Honestly, emulating GBC was a lot easier than the NES. Pan Docs are tremendously well documented and I was able to emulate almost
everything in about a week or so. I strongly recommend as your first emulator if you want to try yourself.

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
