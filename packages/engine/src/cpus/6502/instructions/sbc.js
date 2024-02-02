import { uint8sub } from '../../../utils'
import { AddressingMode, CycleType } from '..'

/**
 * SuBtract with Carry
 *
 * A,Z,C,N = A-M-(1-C)
 *
 * Affects Flags: N V Z C
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Immediate     SBC #$44      $E9  2   2
 * Zero Page     SBC $44       $E5  2   3
 * Zero Page,X   SBC $44,X     $F5  2   4
 * Absolute      SBC $4400     $ED  3   4
 * Absolute,X    SBC $4400,X   $FD  3   4+
 * Absolute,Y    SBC $4400,Y   $F9  3   4+
 * Indirect,X    SBC ($44,X)   $E1  2   6
 * Indirect,Y    SBC ($44),Y   $F1  2   5+
 *
 * + add 1 cycle if page boundary crossed
 */
export function* sbc(mode, addr) {
  const a = this.acc
  const b = mode === AddressingMode.IMM ? addr : this.read(Array.isArray(addr) ? addr[0] : addr)
  const [result, carry] = uint8sub(a, b, this.carry ? 0 : 1)
  this.acc = result
  this.zero = result === 0
  this.negative = (result & 0x80) > 0
  this.carry = !carry
  this.overflow = ((a ^ this.acc) & ((255 - b) ^ this.acc) & 0x80) > 0
  yield CycleType.GET
}
