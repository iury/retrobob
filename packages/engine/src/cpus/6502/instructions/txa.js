import { CycleType } from '..'

/**
 * Transfer X to A
 *
 * A = X
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       TXA           $8A  1   2
 */
export function* txa() {
  this.acc = this.x
  this.zero = this.acc === 0
  this.negative = (this.acc & 0x80) > 0
  yield CycleType.GET
}
