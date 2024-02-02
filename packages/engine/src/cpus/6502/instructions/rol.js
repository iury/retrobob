import { AddressingMode, CycleType } from '..'

/**
 * ROtate Left
 *
 * Affects Flags: N Z C
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Accumulator   ROL A         $2A  1   2
 * Zero Page     ROL $44       $26  2   5
 * Zero Page,X   ROL $44,X     $36  2   6
 * Absolute      ROL $4400     $2E  3   6
 * Absolute,X    ROL $4400,X   $3E  3   7
 */
export function* rol(mode, addr) {
  if (mode === AddressingMode.ACC) {
    const c = this.carry ? 1 : 0
    this.carry = (this.acc & 0x80) > 0
    this.acc = ((this.acc << 1) | c) % 256
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

    const c = this.carry ? 1 : 0
    this.carry = (b & 0x80) > 0
    b = ((b << 1) | c) % 256
    this.write(addr, b)
    this.zero = b === 0
    this.negative = (b & 0x80) > 0
    yield CycleType.PUT
  }
}
