import { CycleType } from '..'

/**
 * Hardware Interrupt
 *
 * Affects Flags: B
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       ---           ---  -   7
 */
export function* irq(pcl, pch, suppressWrites = false) {
  this.breakCommand = false
  this.opcode = 0

  this.fetch()
  if (--this.pc < 0) this.pc = 0xffff
  yield CycleType.GET

  this.fetch()
  if (--this.pc < 0) this.pc = 0xffff
  yield CycleType.GET

  if (!suppressWrites) this.write(0x100 | this.sp, this.pc >>> 8)
  if (--this.sp < 0) this.sp = 0xff
  yield CycleType.PUT

  if (!suppressWrites) this.write(0x100 | this.sp, this.pc & 0xff)
  if (--this.sp < 0) this.sp = 0xff
  yield CycleType.PUT

  if (!suppressWrites) this.write(0x100 | this.sp, this.status & ~0x10)
  if (--this.sp < 0) this.sp = 0xff
  yield CycleType.PUT

  this.pc &= ~0xff
  this.pc |= this.read(pch)
  this.interruptDisabled = true
  yield CycleType.GET

  this.pc &= 0xff
  this.pc <<= 8
  this.pc |= this.read(pcl)
  yield CycleType.GET
}
