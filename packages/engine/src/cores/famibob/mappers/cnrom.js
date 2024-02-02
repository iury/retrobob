// CNROM Mapper (iNES ID 003)
//
// PRG capacity: 16K or 32K
// PRG ROM window: n/a
// PRG RAM: none
// CHR ROM capacity: 32K
// CHR ROM window: 8K
// Nametable mirroring: fixed vertical or horizontal mirroring
//
// PPU $0000-$1FFF: 8 KB switchable CHR ROM bank

import { inRange } from '../../../utils'
import { Mirroring } from '..'

export class CNROM {
  constructor(cartridge) {
    console.log('Mapper: CNROM')

    this.mirroring = cartridge.mirroring
    this.vram = new Array(0x800).fill(0)
    this.prgRom = cartridge.prgData
    this.chrRom = cartridge.chrData
    this.bank = 0
  }

  convertAddress(address) {
    if (inRange(address, 0x0000, 0x1fff)) return (this.bank * 0x2000 + address) % this.chrRom.length
    else if (inRange(address, 0x8000, 0xffff)) return address % this.prgRom.length
    else if (inRange(address, 0x2000, 0x3fff)) {
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
      if (inRange(address, 0x2000, 0x3fff)) this.vram[addr] = value
      else if (inRange(address, 0x8000, 0xffff)) this.bank = value & 0xf
    }
  }
}
