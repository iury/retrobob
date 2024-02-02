import { AddressingMode, CycleType } from '..'

/**
 * Bitwise AND with accumulator
 *
 * A,Z,N = A&M
 *
 * Affects Flags: N Z
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Immediate     AND #$44      $29  2   2
 * Zero Page     AND $44       $25  2   3
 * Zero Page,X   AND $44,X     $35  2   4
 * Absolute      AND $4400     $2D  3   4
 * Absolute,X    AND $4400,X   $3D  3   4+
 * Absolute,Y    AND $4400,Y   $39  3   4+
 * Indirect,X    AND ($44,X)   $21  2   6
 * Indirect,Y    AND ($44),Y   $31  2   5+
 *
 * + add 1 cycle if page boundary crossed
 */
export function* and(mode, addr) {
  const a = this.acc
  const b = mode === AddressingMode.IMM ? addr : this.read(Array.isArray(addr) ? addr[0] : addr)
  this.acc = a & b
  this.zero = this.acc === 0
  this.negative = (this.acc & 0x80) > 0
  yield CycleType.GET
}
