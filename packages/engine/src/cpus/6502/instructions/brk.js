import { CycleType } from '..'

/**
 * BReaK
 *
 * Affects Flags: B
 *
 * push PC, push P, JMP (0xFFFF/E)
 *
 * Affects Flags: B
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       BRK           $00  1   7
 */
export function* brk() {
  this.breakCommand = true
  this.fetch()
  yield CycleType.GET

  this.write(0x100 | this.sp, this.pc >>> 8)
  if (--this.sp < 0) this.sp = 0xff
  yield CycleType.PUT

  this.write(0x100 | this.sp, this.pc & 0xff)
  if (--this.sp < 0) this.sp = 0xff
  yield CycleType.PUT

  const nmi = this.nmiRequested

  this.write(0x100 | this.sp, this.status | 0x10)
  if (--this.sp < 0) this.sp = 0xff
  yield CycleType.PUT

  if (nmi) {
    this.pc &= ~0xff
    this.pc |= this.read(0xfffa)
    this.interruptDisabled = true
    yield CycleType.GET
    this.pc &= 0xff
    this.pc <<= 8
    this.pc |= this.read(0xfffb)
    yield CycleType.GET
  } else {
    this.pc &= ~0xff
    this.pc |= this.read(0xfffe)
    this.interruptDisabled = true
    yield CycleType.GET
    this.pc &= 0xff
    this.pc <<= 8
    this.pc |= this.read(0xffff)
    yield CycleType.GET
  }
}
