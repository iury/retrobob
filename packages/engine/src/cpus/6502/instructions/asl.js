import { AddressingMode, CycleType } from '..'

/**
 * Arithmetic Shift Left
 *
 * A,Z,C,N = M*2 or M,Z,C,N = M*2
 *
 * Affects Flags: N Z C
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Accumulator   ASL A         $0A  1   2
 * Zero Page     ASL $44       $06  2   5
 * Zero Page,X   ASL $44,X     $16  2   6
 * Absolute      ASL $4400     $0E  3   6
 * Absolute,X    ASL $4400,X   $1E  3   7
 */
export function* asl(mode, addr) {
  if (mode === AddressingMode.ACC) {
    this.carry = (this.acc & 0x80) > 0
    this.acc = (this.acc << 1) % 256
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

    this.carry = (b & 0x80) > 0
    b = (b << 1) % 256
    this.write(addr, b)
    this.zero = b === 0
    this.negative = (b & 0x80) > 0
    yield CycleType.PUT
  }
}
