// UxROM Mapper (iNES ID 002)
//
// PRG capacity: 256K / 4096K
// PRG ROM window: 16K + 16K fixed
// PRG RAM: none
// CHR capacity: 8K
// CHR window: n/a
// Nametable mirroring: fixed vertical or horizontal mirroring
//
// CPU $8000-$BFFF: 16 KB switchable PRG ROM bank
// CPU $C000-$FFFF: 16 KB PRG ROM bank, fixed to the last bank

import { inRange } from '../../../utils'
import { Mirroring } from '..'

export class UxROM {
  constructor(cartridge) {
    console.log('Mapper: UxROM')

    this.mirroring = cartridge.mirroring
    this.vram = new Array(0x800).fill(0)
    this.prgRom = cartridge.prgData
    this.bank = 0

    this.chrRom = new Array(
      cartridge.chrRomSize + (cartridge.chrRamSize ? cartridge.chrRamSize : 0x2000 - cartridge.chrRomSize),
    )
  }

  convertAddress(address) {
    if (inRange(address, 0x0000, 0x1fff)) return address % this.chrRom.length
    if (inRange(address, 0x8000, 0xbfff)) return this.bank * 0x4000 + (address % 0x8000)
    if (inRange(address, 0xc000, 0xffff)) return this.prgRom.length - 0x4000 + (address % 0xc000)

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
    }
    return address & 0xff
  }

  write(address, value) {
    const addr = this.convertAddress(address)
    if (addr !== null) {
      if (inRange(address, 0x0000, 0x1fff)) this.chrRom[addr] = value
      if (inRange(address, 0x2000, 0x3fff)) this.vram[addr] = value
      if (inRange(address, 0x8000, 0xffff)) this.bank = value & 0xf
    }
  }
}
