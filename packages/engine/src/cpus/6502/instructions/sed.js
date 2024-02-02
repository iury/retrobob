import { CycleType } from '..'

/**
 * Set Decimal Mode
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       SED           $F8  1   2
 */
export function* sed() {
  this.decimalMode = true
  yield CycleType.GET
}
