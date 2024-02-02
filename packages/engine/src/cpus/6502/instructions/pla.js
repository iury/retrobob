import { CycleType } from '..'

/**
 * PulL Accumulator (from the stack)
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       PLA           $68  1   4
 *
 * Affects Flags: N Z
 */
export function* pla() {
  this.fetch()
  if (--this.pc < 0) this.pc = 0xffff
  yield CycleType.GET

  if (++this.sp > 0xff) this.sp = 0
  yield CycleType.GET

  this.acc = this.read(0x100 | this.sp)
  this.zero = this.acc === 0
  this.negative = (this.acc & 0x80) > 0
  yield CycleType.GET
}
