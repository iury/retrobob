import { AddressingMode, CycleType } from '..'

/**
 * LoaD Accumulator
 *
 * A,Z,N = M
 *
 * Affects Flags: N Z
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Immediate     LDA #$44      $A9  2   2
 * Zero Page     LDA $44       $A5  2   3
 * Zero Page,X   LDA $44,X     $B5  2   4
 * Absolute      LDA $4400     $AD  3   4
 * Absolute,X    LDA $4400,X   $BD  3   4+
 * Absolute,Y    LDA $4400,Y   $B9  3   4+
 * Indirect,X    LDA ($44,X)   $A1  2   6
 * Indirect,Y    LDA ($44),Y   $B1  2   5+
 *
 * + add 1 cycle if page boundary crossed
 */
export function* lda(mode, addr) {
  this.acc = mode === AddressingMode.IMM ? addr : this.read(Array.isArray(addr) ? addr[0] : addr)
  this.zero = this.acc === 0
  this.negative = (this.acc & 0x80) > 0
  yield CycleType.GET
}
