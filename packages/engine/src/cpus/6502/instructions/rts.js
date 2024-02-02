import { CycleType } from '..'

/**
 * ReTurn from Subroutine
 *
 * pull PC, PC++, JMP
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       RTS           $60  1   6
 */
export function* rts() {
  this.fetch()
  if (--this.pc < 0) this.pc = 0xffff
  yield CycleType.GET

  if (++this.sp > 0xff) this.sp = 0
  yield CycleType.GET

  this.pc = this.read(0x100 | this.sp)
  if (++this.sp > 0xff) this.sp = 0
  yield CycleType.GET

  this.pc |= this.read(0x100 | this.sp) << 8
  yield CycleType.GET

  if (this.pc++ > 0xffff) this.pc = 0
  yield CycleType.GET
}
