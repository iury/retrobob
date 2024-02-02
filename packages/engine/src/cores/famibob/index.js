import { Cartridge } from './cartridge'
import { MMU } from './mmu'
import { PPU } from './ppu'
import { Input } from './input'
import { Core } from './core'
import { Clock, RunOption } from './clock'

/** @enum */
export const Mirroring = {
  HORIZONTAL: 1,
  VERTICAL: 2,
  SINGLE_SCREEN: 3,
  FOUR_SCREEN: 4,
}

/** @enum */
export const Region = {
  NTSC: 1,
  PAL: 2,
}

export { Core, Cartridge, MMU, PPU, Input, Clock, RunOption }
