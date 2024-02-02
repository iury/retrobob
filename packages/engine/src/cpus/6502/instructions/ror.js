import { AddressingMode, CycleType } from '..'

/**
 * ROtate Right
 *
 * Affects Flags: N Z C
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Accumulator   ROR A         $6A  1   2
 * Zero Page     ROR $44       $66  2   5
 * Zero Page,X   ROR $44,X     $76  2   6
 * Absolute      ROR $4400     $6E  3   6
 * Absolute,X    ROR $4400,X   $7E  3   7
 */
export function* ror(mode, addr) {
  if (mode === AddressingMode.ACC) {
    const c = this.carry ? 0x80 : 0
    this.carry = (this.acc & 0x1) > 0
    this.acc = (this.acc >>> 1) | c
    this.zero = this.acc === 0
    this.negative = (this.acc & 0x80) > 0
    yield CycleType.GET
  } else {
    if (Array.isArray(addr) && !addr[1]) {
      this.read(addr[0])
      yield CycleType.GET
    }

    addr = Array.isArray(addr) ? addr[0] : addr
    let b = this.read(addr)
    yield CycleType.GET

    this.write(addr, b)
    yield CycleType.PUT

    const c = this.carry ? 0x80 : 0
    this.carry = (b & 0x1) > 0
    b = (b >>> 1) | c
    this.write(addr, b)
    this.zero = b === 0
    this.negative = (b & 0x80) > 0
    yield CycleType.PUT
  }
}
