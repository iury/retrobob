import { CycleType } from '..'

/**
 * Set Carry
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       SEC           $38  1   2
 */
export function* sec() {
  this.carry = true
  yield CycleType.GET
}
