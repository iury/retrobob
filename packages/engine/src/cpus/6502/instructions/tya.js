import { CycleType } from '..'

/**
 * Transfer Y to A
 *
 * A = Y
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       TYA           $98  1   2
 */
export function* tya() {
  this.acc = this.y
  this.zero = this.acc === 0
  this.negative = (this.acc & 0x80) > 0
  yield CycleType.GET
}
