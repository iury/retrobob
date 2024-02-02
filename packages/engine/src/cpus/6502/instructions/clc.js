import { CycleType } from '..'

/**
 * Clear Carry
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       CLC           $18  1   2
 */
export function* clc() {
  this.carry = false
  yield CycleType.GET
}
