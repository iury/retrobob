import { CycleType } from '..'

/**
 * Clear Interrupt Disabled
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       CLI           $58  1   2
 */
export function* cli() {
  this.interruptDisabled = false
  yield CycleType.GET
}
