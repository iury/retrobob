import { CycleType } from '..'

/**
 * INcrement X
 *
 * X,Z,N = X+1
 *
 * Affects Flags: N Z
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       INX           $E8  1   2
 */
export function* inx() {
  if (++this.x > 255) this.x = 0
  this.zero = this.x === 0
  this.negative = (this.x & 0x80) > 0
  yield CycleType.GET
}
