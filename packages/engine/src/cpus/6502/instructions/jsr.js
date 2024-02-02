import { CycleType } from '..'

/**
 * Jump to SubRoutine
 *
 * push PC-1, JMP
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Absolute      JSR $5597     $20  3   6
 */
export function* jsr(mode, addr) {
  if (--this.pc < 0) this.pc = 0xffff

  this.write(0x100 | this.sp, this.pc >>> 8)
  if (--this.sp < 0) this.sp = 0xff
  yield CycleType.PUT

  this.write(0x100 | this.sp, this.pc & 0xff)
  if (--this.sp < 0) this.sp = 0xff
  yield CycleType.PUT

  this.pc = addr
  yield CycleType.GET
}
