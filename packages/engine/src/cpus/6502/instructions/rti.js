import { CycleType } from '..'

/**
 * ReTurn from Interrupt
 *
 * pull P, pull PC, JMP
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       RTI           $40  1   6
 */
export function* rti() {
  this.fetch()
  if (--this.pc < 0) this.pc = 0xffff
  yield CycleType.GET

  if (++this.sp > 0xff) this.sp = 0
  yield CycleType.GET

  this.status = this.read(0x100 | this.sp)
  if (++this.sp > 0xff) this.sp = 0
  this.breakCommand = false
  yield CycleType.GET

  this.pc = this.read(0x100 | this.sp)
  if (++this.sp > 0xff) this.sp = 0
  yield CycleType.GET

  this.pc |= this.read(0x100 | this.sp) << 8
  yield CycleType.GET
}
