import { CycleType } from '..'

/**
 * Clear Decimal Mode
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       CLD           $D8  1   2
 */
export function* cld() {
  this.decimalMode = false
  yield CycleType.GET
}
