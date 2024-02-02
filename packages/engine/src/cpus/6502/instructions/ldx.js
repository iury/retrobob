import { AddressingMode, CycleType } from '..'

/**
 * LoaD X
 *
 * X,Z,N = M
 *
 * Affects Flags: N Z
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Immediate     LDX #$44      $A2  2   2
 * Zero Page     LDX $44       $A6  2   3
 * Zero Page,Y   LDX $44,Y     $B6  2   4
 * Absolute      LDX $4400     $AE  3   4
 * Absolute,Y    LDX $4400,Y   $BE  3   4+
 *
 * + add 1 cycle if page boundary crossed
 */
export function* ldx(mode, addr) {
  this.x = mode === AddressingMode.IMM ? addr : this.read(Array.isArray(addr) ? addr[0] : addr)
  this.zero = this.x === 0
  this.negative = (this.x & 0x80) > 0
  yield CycleType.GET
}
