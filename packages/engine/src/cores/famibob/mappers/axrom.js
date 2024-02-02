// AxROM Mapper (iNES ID 007)
//
// PRG capacity: 256K
// PRG ROM window: 32K
// PRG RAM: none
// CHR capacity: 8K
// CHR window: n/a
// Nametable mirroring: 1 switchable
//
// CPU $8000-$FFFF: 32 KB switchable PRG ROM bank

import { inRange } from '../../../utils'

export class AxROM {
  constructor(cartridge) {
    console.log('Mapper: AxROM')

    this.mirroring = cartridge.mirroring
    this.vram = new Array(0x800).fill(0)
    this.prgRom = cartridge.prgData
    this.chrRom = cartridge.chrData.length ? cartridge.chrData : new Array(cartridge.chrRamSize || 0x2000)
    this.bank = 0
    this.page2 = false
  }

  convertAddress(address) {
    if (inRange(address, 0x0000, 0x1fff)) return this.chrRom.length ? address % this.chrRom.length : null
    else if (inRange(address, 0x8000, 0xffff))
      return this.prgRom.length ? (this.bank * 0x8000 + (address % 0x8000)) % this.prgRom.length : null
    else if (inRange(address, 0x2000, 0x3fff)) {
      return this.page2 ? (address % 0x400) + 0x400 : address % 0x400
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
      else if (inRange(address, 0x2000, 0x3fff)) this.vram[addr] = value
      else if (inRange(address, 0x8000, 0xffff)) {
        this.bank = value & 0x7
        this.page2 = (value & 0x10) > 0
      }
    }
  }
}
