import { CycleType } from '..'

/**
 * DEcrement Y
 *
 * Y,Z,N = Y-1
 *
 * Affects Flags: N Z
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       DEY           $88  1   2
 */
export function* dey() {
  if (--this.y < 0) this.y = 0xff
  this.zero = this.y === 0
  this.negative = (this.y & 0x80) > 0
  yield CycleType.GET
}
