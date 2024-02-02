import { CycleType } from '..'

/**
 * Clear oVerflow
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       CLV           $B8  1   2
 */
export function* clv() {
  this.overflow = false
  yield CycleType.GET
}
