import { CycleType } from '..'

/**
 * PusH Processor flags (in the stack)
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       PHP           $08  1   3
 */
export function* php() {
  this.fetch()
  if (--this.pc < 0) this.pc = 0xffff
  yield CycleType.GET

  this.write(0x100 | this.sp, this.status | 0x10)
  if (--this.sp < 0) this.sp = 0xff
  yield CycleType.PUT
}
