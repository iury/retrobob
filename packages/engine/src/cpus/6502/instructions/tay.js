import { CycleType } from '..'

/**
 * Transfer Accumulator to Y
 *
 * Y = A
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       TAY           $A8  1   2
 */
export function* tay() {
  this.y = this.acc
  this.zero = this.y === 0
  this.negative = (this.y & 0x80) > 0
  yield CycleType.GET
}
