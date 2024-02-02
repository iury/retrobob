import { AddressingMode, CycleType } from '..'

/**
 * LoaD Y
 *
 * Y,Z,N = M
 *
 * Affects Flags: N Z
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Immediate     LDY #$44      $A0  2   2
 * Zero Page     LDY $44       $A4  2   3
 * Zero Page,X   LDY $44,X     $B4  2   4
 * Absolute      LDY $4400     $AC  3   4
 * Absolute,X    LDY $4400,X   $BC  3   4+
 *
 * + add 1 cycle if page boundary crossed
 */
export function* ldy(mode, addr) {
  this.y = mode === AddressingMode.IMM ? addr : this.read(Array.isArray(addr) ? addr[0] : addr)
  this.zero = this.y === 0
  this.negative = (this.y & 0x80) > 0
  yield CycleType.GET
}
