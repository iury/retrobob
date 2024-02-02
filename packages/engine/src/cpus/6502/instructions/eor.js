import { AddressingMode, CycleType } from '..'

/**
 * Bitwise Exclusive OR (XOR)
 *
 * A,Z,N = A^M
 *
 * Affects Flags: N Z
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Immediate     EOR #$44      $49  2   2
 * Zero Page     EOR $44       $45  2   3
 * Zero Page,X   EOR $44,X     $55  2   4
 * Absolute      EOR $4400     $4D  3   4
 * Absolute,X    EOR $4400,X   $5D  3   4+
 * Absolute,Y    EOR $4400,Y   $59  3   4+
 * Indirect,X    EOR ($44,X)   $41  2   6
 * Indirect,Y    EOR ($44),Y   $51  2   5+
 *
 * + add 1 cycle if page boundary crossed
 */
export function* eor(mode, addr) {
  const a = this.acc
  const b = mode === AddressingMode.IMM ? addr : this.read(Array.isArray(addr) ? addr[0] : addr)
  this.acc = a ^ b
  this.zero = this.acc === 0
  this.negative = (this.acc & 0x80) > 0
  yield CycleType.GET
}
