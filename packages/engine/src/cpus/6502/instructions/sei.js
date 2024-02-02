import { CycleType } from '..'

/**
 * Set Interrupt Disabled
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       SEI           $78  1   2
 */
export function* sei() {
  this.interruptDisabled = true
  yield CycleType.GET
}
