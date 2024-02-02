// MMC1 Mapper (iNES ID 001)
//
// SxROM
//
// PRG ROM size: 256K (512K)
// PRG ROM window: 16K + 16K fixed or 32K
// PRG RAM: 32K
// PRG RAM window: 8K
// CHR capacity: 128K
// CHR window: 4K + 4K or 8K
// Nametable mirroring: H, V, or 1, switchable
//
// PPU $0000-$0FFF: 4 KB switchable CHR bank
// PPU $1000-$1FFF: 4 KB switchable CHR bank
// CPU $6000-$7FFF: 8 KB PRG RAM bank, (optional)
// CPU $8000-$BFFF: 16 KB PRG ROM bank, either switchable or fixed to the first bank
// CPU $C000-$FFFF: 16 KB PRG ROM bank, either fixed to the last bank or switchable

import { inRange } from '../../../utils'
import { Mirroring } from '..'

export class MMC1 {
  constructor(cartridge) {
    console.log('Mapper: MMC1 (SxROM)')

    this.mirroring = cartridge.mirroring
    this.vram = new Array(0x800).fill(0)
    this.prgRom = cartridge.prgData
    this.chrRom = cartridge.chrData
    this.prgRam = new Array(cartridge.prgRamSize)
    this.loadRegister = 0
    this.chrBank1 = 0
    this.chrBank2 = 0
    this.prgRomBank = 0
    this.ctrl = 0xc | (this.mirroring === Mirroring.HORIZONTAL ? 3 : this.mirroring === Mirroring.VERTICAL ? 2 : 0)

    if (this.chrRom.length === 0) {
      this.chrRom = new Array(cartridge.chrRamSize || 0x8000)
    }

    if (cartridge.trainer) {
      for (let i = 0; i < 512; i++) this.prgRam[0x1000 + i] = cartridge.trainerData[i] ?? 0
    }
  }

  convertAddress(address) {
    if (inRange(address, 0x0000, 0x1fff)) {
      return (
        ((this.ctrl & 0x10) === 0
          ? ((this.chrBank1 >>> 1) * 0x2000) | address
          : ((address < 0x1000 ? this.chrBank1 : this.chrBank2) * 0x1000) | address % 0x1000) % this.chrRom.length
      )
    } else if (inRange(address, 0x2000, 0x3fff)) {
      switch (this.ctrl & 0x3) {
        case 0:
          return address & 0x3ff
        case 1:
          return (address & 0x3ff) + 0x400
        case 2:
          return address & 0x7ff
        case 3:
          return (address & 0x3ff) | ((address & 0x800) >>> 1)
      }
    } else if (inRange(address, 0x6000, 0x7fff)) {
      return (address % 0x6000) % this.prgRam.length
    } else if (inRange(address, 0x8000, 0xffff)) {
      var mode = this.ctrl & 0xc
      if (mode >= 0x8) {
        if (address >= 0x8000 && address <= 0xbfff) {
          if (mode === 0x8) {
            return (address % 0x8000) % this.prgRom.length
          } else {
            return ((address % 0x8000) + this.prgRomBank * 0x4000) % this.prgRom.length
          }
        } else {
          if (mode === 0x8) {
            return ((address % 0xc000) + this.prgRomBank * 0x4000) % this.prgRom.length
          } else {
            return (this.prgRom.length - 0x4000 + (address % 0xc000)) % this.prgRom.length
          }
        }
      } else {
        return ((address % 0x8000) + (this.prgRomBank >>> 1) * 0x8000) % this.prgRom.length
      }
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
      if (inRange(address, 0x0000, 0x1fff)) this.chrRom[addr] = value
      else if (inRange(address, 0x2000, 0x3fff)) this.vram[addr] = value
      else if (inRange(address, 0x6000, 0x7fff)) this.prgRam[addr] = value
      else if (inRange(address, 0x8000, 0xffff)) {
        if ((value & 0x80) > 0) {
          this.loadRegister = 1 << 4
          this.ctrl |= 0xc
          return
        } else {
          const mark = this.loadRegister & 1
          this.loadRegister = (this.loadRegister >>> 1) | ((value & 1) << 4)
          if (mark) {
            if (inRange(address, 0x8000, 0x9fff)) this.ctrl = this.loadRegister
            else if (inRange(address, 0xa000, 0xbfff)) this.chrBank1 = this.loadRegister
            else if (inRange(address, 0xc000, 0xdfff)) this.chrBank2 = this.loadRegister
            else if (inRange(address, 0xe000, 0xffff)) this.prgRomBank = this.loadRegister & 0xf
            this.loadRegister = 1 << 4
          }
        }
      }
    }
  }
}
