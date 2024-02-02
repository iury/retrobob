import { AddressingMode, CycleType } from '..'

/**
 * ComPare Y register
 *
 * Z,C,N = Y-M
 *
 * Affects Flags: N Z C
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Immediate     CPY #$44      $C0  2   2
 * Zero Page     CPY $44       $C4  2   3
 * Absolute      CPY $4400     $CC  3   4
 */
export function* cpy(mode, addr) {
  const a = this.y
  const b = mode === AddressingMode.IMM ? addr : this.read(Array.isArray(addr) ? addr[0] : addr)
  this.carry = a >= b
  this.zero = a === b
  let v = a - b
  if (v < 0) v = 256 + v
  this.negative = (v & 0x80) > 0
  yield CycleType.GET
}
