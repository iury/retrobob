// MMC2 Mapper (iNES ID 009)
//
// PRG capacity: 128K
// PRG ROM window: 8K + 24K fixed
// PRG RAM: none
// CHR capacity: 128K
// CHR window: 4K + 4K (triggered)
// Nametable mirroring: H or V, switchable
//
// PPU $0000-$0FFF: Two 4 KB switchable CHR ROM banks
// PPU $1000-$1FFF: Two 4 KB switchable CHR ROM banks
// CPU $8000-$9FFF: 8 KB switchable PRG ROM bank
// CPU $A000-$FFFF: Three 8 KB PRG ROM banks, fixed to the last three banks

import { inRange } from '../../../utils'
import { Mirroring } from '..'

export class MMC2 {
  constructor(cartridge) {
    console.log('Mapper: MMC2')

    this.mirroring = cartridge.mirroring
    this.vram = new Array(0x800).fill(0)
    this.prgRom = cartridge.prgData
    this.chrRom = cartridge.chrData
    this.latch0 = 0xfd
    this.latch1 = 0xfd
    this.chrBankFD0 = 0
    this.chrBankFE0 = 0
    this.chrBankFD1 = 0
    this.chrBankFE1 = 0
    this.prgBank = 0
  }

  convertAddress(address) {
    if (inRange(address, 0x0000, 0x0fff))
      return (
        ((this.latch0 === 0xfd ? this.chrBankFD0 : this.chrBankFE0) * 0x1000 + (address % 0x1000)) % this.chrRom.length
      )
    else if (inRange(address, 0x1000, 0x1fff))
      return (
        ((this.latch1 === 0xfd ? this.chrBankFD1 : this.chrBankFE1) * 0x1000 + (address % 0x1000)) % this.chrRom.length
      )
    else if (inRange(address, 0x8000, 0x9fff)) return (this.prgBank * 0x2000 + (address % 0x8000)) % this.prgRom.length
    else if (inRange(address, 0xa000, 0xffff))
      return (this.prgRom.length - 0x6000 + (address % 0xa000)) % this.prgRom.length
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
      if (inRange(address, 0x0000, 0x1fff)) {
        if (address === 0x0fd8) this.latch0 = 0xfd
        else if (address === 0x0fe8) this.latch0 = 0xfe
        else if (address >= 0x1fd8 && address <= 0x1fdf) this.latch1 = 0xfd
        else if (address >= 0x1fe8 && address <= 0x1fef) this.latch1 = 0xfe
        return this.chrRom[addr] ?? 0
      } else if (inRange(address, 0x2000, 0x3fff)) return this.vram[addr] ?? 0
      else if (inRange(address, 0x8000, 0xffff)) return this.prgRom[addr] ?? 0
    }
    return address & 0xff
  }

  write(address, value) {
    const addr = this.convertAddress(address)
    if (addr !== null) {
      if (inRange(address, 0x2000, 0x3fff)) this.vram[addr] = value
      else if (inRange(address, 0xa000, 0xafff)) this.prgBank = value & 0xf
      else if (inRange(address, 0xb000, 0xbfff)) this.chrBankFD0 = value & 0xf
      else if (inRange(address, 0xc000, 0xcfff)) this.chrBankFE0 = value & 0xf
      else if (inRange(address, 0xd000, 0xdfff)) this.chrBankFD1 = value & 0xf
      else if (inRange(address, 0xe000, 0xefff)) this.chrBankFE1 = value & 0xf
      else if (inRange(address, 0xf000, 0xffff))
        this.mirroring = (value & 1) === 0 ? Mirroring.VERTICAL : Mirroring.HORIZONTAL
    }
  }
}
