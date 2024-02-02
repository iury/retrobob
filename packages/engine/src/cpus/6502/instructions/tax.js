import { CycleType } from '..'

/**
 * Transfer Accumulator to X
 *
 * X = A
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       TAX           $AA  1   2
 */
export function* tax() {
  this.x = this.acc
  this.zero = this.x === 0
  this.negative = (this.x & 0x80) > 0
  yield CycleType.GET
}
