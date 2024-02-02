import { irq } from './instructions/irq'
import { AddressingMode, Opcode, Instruction } from '.'

/** @enum */
export const CycleType = {
  GET: 'GET',
  PUT: 'PUT',
}

export class CPU {
  constructor(mmu) {
    this.reset()
    this.read = mmu.read.bind(mmu)
    this.write = mmu.write.bind(mmu)
  }

  reset() {
    this.pc = 0
    this.sp = 0
    this.acc = 0
    this.x = 0
    this.y = 0

    this.carry = false
    this.zero = false
    this.interruptDisabled = true
    this.decimalMode = false
    this.breakCommand = false
    this.overflow = false
    this.negative = false

    this.nmiRequested = false
    this.rstRequested = false
    this.irqRequested = false

    this.opcode = null
    this.cycle = 0
  }

  get status() {
    return (
      0x20 |
      (this.carry ? 0x01 : 0) |
      (this.zero ? 0x02 : 0) |
      (this.interruptDisabled ? 0x04 : 0) |
      (this.decimalMode ? 0x08 : 0) |
      (this.breakCommand ? 0x10 : 0) |
      (this.overflow ? 0x40 : 0) |
      (this.negative ? 0x80 : 0)
    )
  }

  set status(value) {
    this.carry = (value & 0x01) > 0
    this.zero = (value & 0x02) > 0
    this.interruptDisabled = (value & 0x04) > 0
    this.decimalMode = (value & 0x08) > 0
    this.breakCommand = (value & 0x10) > 0
    this.overflow = (value & 0x40) > 0
    this.negative = (value & 0x80) > 0
  }

  fetch() {
    const value = this.read(this.pc & 0xffff)
    if (++this.pc > 0xffff) this.pc = 0
    return value
  }

  checkPageCrossing(address, offset) {
    return (address & 0xff00) !== ((address + offset) & 0xff00)
  }

  *resolveAddress(mode) {
    switch (mode) {
      case AddressingMode.IMM: {
        return this.fetch()
      }

      case AddressingMode.REL: {
        const offset = this.fetch()
        yield CycleType.GET
        return (offset & 0x80) > 0 ? -256 + offset : offset
      }

      case AddressingMode.ZPG: {
        const value = this.fetch()
        yield CycleType.GET
        return value
      }

      case AddressingMode.ZPX: {
        const value = this.fetch()
        yield CycleType.GET
        this.read(value)
        yield CycleType.GET
        return (value + this.x) & 0xff
      }

      case AddressingMode.ZPY: {
        const value = this.fetch()
        yield CycleType.GET
        this.read(value)
        yield CycleType.GET
        return (value + this.y) & 0xff
      }

      case AddressingMode.ABS: {
        let value = this.fetch()
        yield CycleType.GET
        value |= this.fetch() << 8
        yield CycleType.GET
        return value
      }

      case AddressingMode.ABX: {
        let value = this.fetch()
        yield CycleType.GET
        value |= this.fetch() << 8
        yield CycleType.GET
        if (this.checkPageCrossing(value, this.x)) {
          this.read((value & 0xff00) | ((value + this.x) & 0xff))
          yield CycleType.GET
          return [(value + this.x) & 0xffff, true]
        }
        return [(value + this.x) & 0xffff, false]
      }

      case AddressingMode.ABY: {
        let value = this.fetch()
        yield CycleType.GET
        value |= this.fetch() << 8
        yield CycleType.GET
        if (this.checkPageCrossing(value, this.y)) {
          this.read((value & 0xff00) | ((value + this.y) & 0xff))
          yield CycleType.GET
          return [(value + this.y) & 0xffff, true]
        }
        return [(value + this.y) & 0xffff, false]
      }

      case AddressingMode.IDX: {
        const value = this.fetch()
        yield CycleType.GET
        this.read(value)
        const pointer = (value + this.x) & 0xff
        yield CycleType.GET
        let addr = this.read(pointer)
        yield CycleType.GET
        addr |= this.read((pointer + 1) & 0xff) << 8
        yield CycleType.GET
        return addr
      }

      case AddressingMode.IDY: {
        const value = this.fetch()
        yield CycleType.GET
        let addr = this.read(value)
        yield CycleType.GET
        addr |= this.read((value + 1) & 0xff) << 8
        yield CycleType.GET
        if (this.checkPageCrossing(addr, this.y)) {
          this.read((addr & 0xff00) | ((addr + this.y) & 0xff))
          yield CycleType.GET
          return [(addr + this.y) & 0xffff, true]
        }
        return [(addr + this.y) & 0xffff, false]
      }
    }
  }

  *run() {
    while (true) {
      if (this.rstRequested) {
        this.rstRequested = false
        yield* irq.call(this, 0xfffc, 0xfffd, true)
      } else if (this.nmiRequested) {
        this.nmiRequested = false
        yield* irq.call(this, 0xfffa, 0xfffb)
      } else if (this.irqRequested) {
        this.irqRequested = false
        if (!this.interruptDisabled) yield* irq.call(this, 0xfffe, 0xffff)
      }

      if (this.cycle !== 1) {
        this.opcode = this.fetch()
        this.cycle = 1
        yield CycleType.GET
      }

      const { fn, addressingMode, instruction } = Opcode[this.opcode]
      let addr

      if (instruction !== Instruction.JMP && instruction !== Instruction.HLT) {
        let g = this.resolveAddress(addressingMode)
        let result = g.next()
        while (true) {
          if (result.done) break
          this.cycle++
          yield result.value
          result = g.next()
        }
        addr = result.value
      }

      let g = fn.call(this, addressingMode, addr)
      let result = g.next()
      while (true) {
        if (result.done) break
        if (instruction !== Instruction.HLT) this.cycle++
        yield result.value
        result = g.next()
      }
    }
  }
}
