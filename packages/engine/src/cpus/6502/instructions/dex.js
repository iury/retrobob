import { CycleType } from '..'

/**
 * DEcrement X
 *
 * X,Z,N = X-1
 *
 * Affects Flags: N Z
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       DEX           $CA  1   2
 */
export function* dex() {
  if (--this.x < 0) this.x = 0xff
  this.zero = this.x === 0
  this.negative = (this.x & 0x80) > 0
  yield CycleType.GET
}
