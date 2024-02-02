import { AddressingMode, CycleType } from '..'

/**
 * ComPare X register
 *
 * Z,C,N = X-M
 *
 * Affects Flags: N Z C
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Immediate     CPX #$44      $E0  2   2
 * Zero Page     CPX $44       $E4  2   3
 * Absolute      CPX $4400     $EC  3   4
 */
export function* cpx(mode, addr) {
  const a = this.x
  const b = mode === AddressingMode.IMM ? addr : this.read(Array.isArray(addr) ? addr[0] : addr)
  this.carry = a >= b
  this.zero = a === b
  let v = a - b
  if (v < 0) v = 256 + v
  this.negative = (v & 0x80) > 0
  yield CycleType.GET
}
