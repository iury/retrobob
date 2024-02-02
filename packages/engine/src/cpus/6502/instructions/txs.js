import { CycleType } from '..'

/**
 * Transfer X to Stack pointer
 *
 * SP = X
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       TXS           $9A  1   2
 */
export function* txs() {
  this.sp = this.x
  yield CycleType.GET
}
