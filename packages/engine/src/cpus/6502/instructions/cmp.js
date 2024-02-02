import { AddressingMode, CycleType } from '..'

/**
 * CoMPare accumulator
 *
 * Z,C,N = A-M
 *
 * Affects Flags: N Z C
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Immediate     CMP #$44      $C9  2   2
 * Zero Page     CMP $44       $C5  2   3
 * Zero Page,X   CMP $44,X     $D5  2   4
 * Absolute      CMP $4400     $CD  3   4
 * Absolute,X    CMP $4400,X   $DD  3   4+
 * Absolute,Y    CMP $4400,Y   $D9  3   4+
 * Indirect,X    CMP ($44,X)   $C1  2   6
 * Indirect,Y    CMP ($44),Y   $D1  2   5+
 *
 * + add 1 cycle if page boundary crossed
 */
export function* cmp(mode, addr) {
  const a = this.acc
  const b = mode === AddressingMode.IMM ? addr : this.read(Array.isArray(addr) ? addr[0] : addr)
  this.carry = a >= b
  this.zero = a === b
  let v = a - b
  if (v < 0) v = 256 + v
  this.negative = (v & 0x80) > 0
  yield CycleType.GET
}
