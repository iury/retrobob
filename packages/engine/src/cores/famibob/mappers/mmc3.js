// MMC3 Mapper (iNES ID 004)
//
// PRG capacity: 512K
// PRG ROM window: 8K + 8K + 16K fixed
// PRG RAM: 8K
// CHR capacity: 256K
// CHR window: 2Kx2 + 1Kx4
// Nametable mirroring: H or V, switchable, or 4 fixed
//
// PPU $0000-$07FF (or $1000-$17FF): 2 KB switchable CHR bank
// PPU $0800-$0FFF (or $1800-$1FFF): 2 KB switchable CHR bank
// PPU $1000-$13FF (or $0000-$03FF): 1 KB switchable CHR bank
// PPU $1400-$17FF (or $0400-$07FF): 1 KB switchable CHR bank
// PPU $1800-$1BFF (or $0800-$0BFF): 1 KB switchable CHR bank
// PPU $1C00-$1FFF (or $0C00-$0FFF): 1 KB switchable CHR bank
// CPU $6000-$7FFF: 8 KB PRG RAM bank (optional)
// CPU $8000-$9FFF (or $C000-$DFFF): 8 KB switchable PRG ROM bank
// CPU $A000-$BFFF: 8 KB switchable PRG ROM bank
// CPU $C000-$DFFF (or $8000-$9FFF): 8 KB PRG ROM bank, fixed to the second-last bank
// CPU $E000-$FFFF: 8 KB PRG ROM bank, fixed to the last bank

import { inRange } from '../../../utils'
import { Mirroring } from '..'

export class MMC3 {
  constructor(cartridge) {
    console.log('Mapper: MMC3')

    this.mirroring = cartridge.mirroring
    this.vram = new Array(this.mirroring !== Mirroring.FOUR_SCREEN ? 0x800 : 0x2000).fill(0)
    this.prgRom = cartridge.prgData
    this.chrRom = cartridge.chrData.length ? cartridge.chrData : new Array(cartridge.chrRamSize || 0x40000)
    this.prgRam = new Array(cartridge.prgRamSize)

    if (cartridge.trainer) {
      for (let i = 0; i < 512; i++) this.prgRam[0x1000 + i] = cartridge.trainerData[i] ?? 0
    }

    this.prevA12 = 0
    this.irqCounter = 0
    this.irqLatch = 0
    this.irqReload = false
    this.irqEnabled = false
    this.irqRequested = false

    this.ctrl = 0
    this.r0 = 0
    this.r1 = 0
    this.r2 = 0
    this.r3 = 0
    this.r4 = 0
    this.r5 = 0
    this.r6 = 0
    this.r7 = 0
  }

  convertAddress(address) {
    if (inRange(address, 0x0000, 0x1fff)) {
      if (this.chrRom.length === 0) return null
      let v = address % 0x0400
      if ((this.ctrl & 0x80) === 0) {
        if (inRange(address, 0x0000, 0x03ff)) v += 0x0400 * this.r0
        else if (inRange(address, 0x0400, 0x07ff)) v += 0x0400 * (this.r0 + 1)
        else if (inRange(address, 0x0800, 0x0bff)) v += 0x0400 * this.r1
        else if (inRange(address, 0x0c00, 0x0fff)) v += 0x0400 * (this.r1 + 1)
        else if (inRange(address, 0x1000, 0x13ff)) v += 0x0400 * this.r2
        else if (inRange(address, 0x1400, 0x17ff)) v += 0x0400 * this.r3
        else if (inRange(address, 0x1800, 0x1bff)) v += 0x0400 * this.r4
        else if (inRange(address, 0x1c00, 0x1fff)) v += 0x0400 * this.r5
      } else {
        if (inRange(address, 0x0000, 0x03ff)) v += 0x0400 * this.r2
        else if (inRange(address, 0x0400, 0x07ff)) v += 0x0400 * this.r3
        else if (inRange(address, 0x0800, 0x0bff)) v += 0x0400 * this.r4
        else if (inRange(address, 0x0c00, 0x0fff)) v += 0x0400 * this.r5
        else if (inRange(address, 0x1000, 0x13ff)) v += 0x0400 * this.r0
        else if (inRange(address, 0x1400, 0x17ff)) v += 0x0400 * (this.r0 + 1)
        else if (inRange(address, 0x1800, 0x1bff)) v += 0x0400 * this.r1
        else if (inRange(address, 0x1c00, 0x1fff)) v += 0x0400 * (this.r1 + 1)
      }
      return v % this.chrRom.length
    }

    if (inRange(address, 0x8000, 0xffff)) {
      if (this.prgRom.length === 0) return null
      let v = address % 0x2000
      if ((this.ctrl & 0x40) === 0) {
        if (inRange(address, 0x8000, 0x9fff)) v += 0x2000 * this.r6
        else if (inRange(address, 0xa000, 0xbfff)) v += 0x2000 * this.r7
        else if (inRange(address, 0xc000, 0xdfff)) v += 0x2000 * (((this.prgRom.length / 0x2000) >>> 0) - 2)
        else if (inRange(address, 0xe000, 0xffff)) v += 0x2000 * (((this.prgRom.length / 0x2000) >>> 0) - 1)
      } else {
        if (inRange(address, 0x8000, 0x9fff)) v += 0x2000 * (((this.prgRom.length / 0x2000) >>> 0) - 2)
        else if (inRange(address, 0xa000, 0xbfff)) v += 0x2000 * this.r7
        else if (inRange(address, 0xc000, 0xdfff)) v += 0x2000 * this.r6
        else if (inRange(address, 0xe000, 0xffff)) v += 0x2000 * (((this.prgRom.length / 0x2000) >>> 0) - 1)
      }
      return v % this.prgRom.length
    }

    if (inRange(address, 0x6000, 0x7fff)) return address % this.prgRam.length

    if (inRange(address, 0x2000, 0x3fff)) {
      if (this.mirroring === Mirroring.HORIZONTAL) return (address & 0x3ff) | ((address & 0x800) >>> 1)
      else if (this.mirroring === Mirroring.VERTICAL) return address & 0x7ff
      else return address & 0x1fff
    }

    return null
  }

  read(address) {
    const addr = this.convertAddress(address)
    if (addr !== null) {
      if (inRange(address, 0x0000, 0x1fff)) {
        this.checkA12(address)
        return this.chrRom[addr] ?? 0
      } else if (inRange(address, 0x2000, 0x3fff)) return this.vram[addr] ?? 0
      else if (inRange(address, 0x8000, 0xffff)) return this.prgRom[addr] ?? 0
      else if (inRange(address, 0x6000, 0x7fff) && this.prgRam.length) return this.prgRam[addr] ?? 0
    }
    return address & 0xff
  }

  write(address, value) {
    const addr = this.convertAddress(address)
    if (addr !== null) {
      if (inRange(address, 0x0000, 0x1fff)) {
        this.checkA12(address)
        this.chrRom[addr] = value
      } else if (inRange(address, 0x2000, 0x3fff)) this.vram[addr] = value
      else if (inRange(address, 0x6000, 0x7fff)) this.prgRam[addr] = value
      else if (inRange(address, 0x8000, 0x9fff)) {
        if (address % 2 === 0) {
          this.ctrl = value
        } else {
          switch (this.ctrl & 0x7) {
            case 0: {
              this.r0 = value & 0xfe
              break
            }
            case 1: {
              this.r1 = value & 0xfe
              break
            }
            case 2: {
              this.r2 = value
              break
            }
            case 3: {
              this.r3 = value
              break
            }
            case 4: {
              this.r4 = value
              break
            }
            case 5: {
              this.r5 = value
              break
            }
            case 6: {
              this.r6 = value & 0x3f
              break
            }
            case 7: {
              this.r7 = value & 0x3f
              break
            }
          }
        }
      } else if (inRange(address, 0xa000, 0xbffe)) {
        if (this.mirroring !== Mirroring.FOUR_SCREEN) {
          this.mirroring = (value & 1) === 0 ? Mirroring.VERTICAL : Mirroring.HORIZONTAL
        }
      } else if (inRange(address, 0xc000, 0xdfff)) {
        if (address % 2 === 0) {
          this.irqLatch = value
        } else {
          this.irqCounter = 0
          this.irqReload = true
        }
      } else if (inRange(address, 0xe000, 0xffff)) {
        if (address % 2 === 0) {
          this.irqEnabled = false
          this.irqOccurred = false
        } else {
          this.irqEnabled = true
        }
      }
    }
  }

  checkA12(address) {
    if ((address & 0x1000) > 0 && this.prevA12 === 0) this.a12Trigger()
    this.prevA12 = (address & 0x1000) > 0 ? 1 : 0
  }

  a12Trigger() {
    if (this.irqCounter === 0 || this.irqReload) {
      this.irqReload = false
      this.irqCounter = this.irqLatch
    } else {
      this.irqCounter--
    }

    if (this.irqCounter === 0 && this.irqEnabled) {
      this.irqRequested = true
    }
  }
}
