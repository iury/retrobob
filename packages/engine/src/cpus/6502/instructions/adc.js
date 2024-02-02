import { uint8add } from '../../../utils'
import { AddressingMode, CycleType } from '..'

/**
 * ADd with Carry
 *
 * A,Z,C,N = A+M+C
 *
 * Affects Flags: N V Z C
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Immediate     ADC #$44      $69  2   2
 * Zero Page     ADC $44       $65  2   3
 * Zero Page,X   ADC $44,X     $75  2   4
 * Absolute      ADC $4400     $6D  3   4
 * Absolute,X    ADC $4400,X   $7D  3   4+
 * Absolute,Y    ADC $4400,Y   $79  3   4+
 * Indirect,X    ADC ($44,X)   $61  2   6
 * Indirect,Y    ADC ($44),Y   $71  2   5+
 *
 * + add 1 cycle if page boundary crossed
 */
export function* adc(mode, addr) {
  const a = this.acc
  const b = mode === AddressingMode.IMM ? addr : this.read(Array.isArray(addr) ? addr[0] : addr)
  const [result, carry] = uint8add(a, b, this.carry ? 1 : 0)
  this.acc = result
  this.zero = result === 0
  this.negative = (result & 0x80) > 0
  this.carry = carry
  this.overflow = ((a ^ result) & (b ^ result) & 0x80) > 0
  yield CycleType.GET
}
