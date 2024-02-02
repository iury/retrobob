// NROM Mapper (iNES ID 000)
//
// NES-NROM-128, NES-NROM-256
//
// PRG ROM size: 16kB for NROM-128, 32kB for NROM-256
// PRG ROM bank size: not bankswitched
// PRG RAM: 2 or 4 kB, not bankswitched
// CHR capacity: 8kB ROM
// CHR bank size: not bankswitched
// Nametable mirroring: fixed vertical or horizontal mirroring
//
// CPU $6000-$7FFF: PRG RAM, mirrored as necessary to fill entire 8kB window
// CPU $8000-$BFFF: first 16kB of ROM
// CPU $C000-$FFFF: last 16kB of ROM (NROM-256) or mirror of $8000-$BFFF (NROM-128)

import { inRange } from '../../../utils'
import { Mirroring } from '..'

export class NROM {
  constructor(cartridge) {
    console.log('Mapper: NROM')

    this.mirroring = cartridge.mirroring
    this.vram = new Array(0x800).fill(0)
    this.prgRom = cartridge.prgData
    this.chrRom = cartridge.chrData
    this.prgRam = new Array(cartridge.prgRamSize)

    if (cartridge.trainer) {
      for (let i = 0; i < 512; i++) this.prgRam[0x1000 + i] = cartridge.trainerData[i] ?? 0
    }
  }

  convertAddress(address) {
    if (inRange(address, 0x0000, 0x1fff)) return address % this.chrRom.length
    if (inRange(address, 0x6000, 0x7fff)) return address % this.prgRam.length
    if (inRange(address, 0x8000, 0xbfff)) return address % 0x4000

    if (inRange(address, 0xc000, 0xffff))
      return this.prgRom.length > 0x4000 ? 0x4000 + (address % 0x4000) : address % 0x4000

    if (inRange(address, 0x2000, 0x3fff)) {
      if (this.mirroring === Mirroring.HORIZONTAL) return (address & 0x3ff) | ((address & 0x800) >>> 1)
      else if (this.mirroring === Mirroring.VERTICAL) return address & 0x7ff
      else return null
    }

    return null
  }

  read(address) {
    const addr = this.convertAddress(address)
    if (addr !== null) {
      if (inRange(address, 0x0000, 0x1fff)) return this.chrRom[addr] ?? 0
      else if (inRange(address, 0x2000, 0x3fff)) return this.vram[addr] ?? 0
      else if (inRange(address, 0x8000, 0xffff)) return this.prgRom[addr] ?? 0
      else if (inRange(address, 0x6000, 0x7fff) && this.prgRam.length) return this.prgRam[addr] ?? 0
    }
    return address & 0xff
  }

  write(address, value) {
    const addr = this.convertAddress(address)
    if (addr !== null) {
      if (inRange(address, 0x2000, 0x3fff)) this.vram[addr] = value
      if (inRange(address, 0x6000, 0x7fff)) this.prgRam[addr] = value
    }
  }
}
