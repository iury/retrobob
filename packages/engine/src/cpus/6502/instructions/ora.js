import { AddressingMode, CycleType } from '..'

/**
 * Bitwise OR with Accumulator
 *
 * A,Z,N = A|M
 *
 * Affects Flags: N Z
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Immediate     ORA #$44      $09  2   2
 * Zero Page     ORA $44       $05  2   3
 * Zero Page,X   ORA $44,X     $15  2   4
 * Absolute      ORA $4400     $0D  3   4
 * Absolute,X    ORA $4400,X   $1D  3   4+
 * Absolute,Y    ORA $4400,Y   $19  3   4+
 * Indirect,X    ORA ($44,X)   $01  2   6
 * Indirect,Y    ORA ($44),Y   $11  2   5+
 *
 * + add 1 cycle if page boundary crossed
 */
export function* ora(mode, addr) {
  const a = this.acc
  const b = mode === AddressingMode.IMM ? addr : this.read(Array.isArray(addr) ? addr[0] : addr)
  this.acc = a | b
  this.zero = this.acc === 0
  this.negative = (this.acc & 0x80) > 0
  yield CycleType.GET
}
