import { CycleType } from '..'

/**
 * INcrement Y
 *
 * Y,Z,N = Y+1
 *
 * Affects Flags: N Z
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       INY           $C8  1   2
 */
export function* iny() {
  if (++this.y > 255) this.y = 0
  this.zero = this.y === 0
  this.negative = (this.y & 0x80) > 0
  yield CycleType.GET
}
