import { CycleType } from '..'

/**
 * PulL Processor flags (from the stack)
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       PLP           $28  1   4
 */
export function* plp() {
  this.fetch()
  if (--this.pc < 0) this.pc = 0xffff
  yield CycleType.GET

  if (++this.sp > 0xff) this.sp = 0
  yield CycleType.GET

  this.status = this.read(0x100 | this.sp)
  this.breakCommand = false
  yield CycleType.GET
}
