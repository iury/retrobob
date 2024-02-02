import { inRange } from '../../utils'

export class MMU {
  constructor(mapperHandler, ppuHandler, apuHandler, inputHandler) {
    this.ram = Array.from({ length: 0x800 }, () => Math.floor(Math.random() * 256))

    this.mapperHandler = mapperHandler
    this.ppuHandler = ppuHandler
    this.apuHandler = apuHandler
    this.inputHandler = inputHandler
  }

  read(address) {
    if (inRange(address, 0x0000, 0x1fff)) return this.ram[address % 0x800] ?? 0
    else if (inRange(address, 0x2000, 0x3fff)) return this.ppuHandler.read(0x2000 + (address % 8))
    else if (address === 0x4015) return this.apuHandler.read(address)
    else if (inRange(address, 0x4000, 0xffff)) {
      let v = this.mapperHandler.read(address)
      if (address === 0x4016 || address === 0x4017) v = 0x40 | this.inputHandler.read(address)
      return v
    }
    return 0
  }

  write(address, value) {
    if (inRange(address, 0x0000, 0x1fff)) this.ram[address % 0x800] = value
    else if (inRange(address, 0x2000, 0x3fff)) return this.ppuHandler.write(0x2000 + (address % 8), value)
    else if (address === 0x4014) return this.ppuHandler.write(address, value)
    else if (address === 0x4016) return this.inputHandler.write(address, value)
    else if (address === 0x4015 || address === 0x4017 || inRange(address, 0x4000, 0x4013))
      return this.apuHandler.write(address, value)
    else if (inRange(address, 0x4020, 0xffff)) return this.mapperHandler.write(address, value)
  }
}
