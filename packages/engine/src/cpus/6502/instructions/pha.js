import { CycleType } from '..'

/**
 * PusH Accumulator (in the stack)
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       PHA           $48  1   3
 */
export function* pha() {
  this.fetch()
  if (--this.pc < 0) this.pc = 0xffff
  yield CycleType.GET

  this.write(0x100 | this.sp, this.acc)
  if (--this.sp < 0) this.sp = 0xff
  yield CycleType.PUT
}
