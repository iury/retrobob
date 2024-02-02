import { AddressingMode, CycleType } from '..'

/**
 * Logical Shift Right
 *
 * A,C,Z,N = A/2 or M,C,Z,N = M/2
 *
 * Affects Flags: N Z C
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Accumulator   LSR A         $4A  1   2
 * Zero Page     LSR $44       $46  2   5
 * Zero Page,X   LSR $44,X     $56  2   6
 * Absolute      LSR $4400     $4E  3   6
 * Absolute,X    LSR $4400,X   $5E  3   7
 */
export function* lsr(mode, addr) {
  if (mode === AddressingMode.ACC) {
    this.carry = (this.acc & 0x1) > 0
    this.acc >>>= 1
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

    this.carry = (b & 0x1) > 0
    b >>>= 1
    this.write(addr, b)
    this.zero = b === 0
    this.negative = (b & 0x80) > 0
    yield CycleType.PUT
  }
}
