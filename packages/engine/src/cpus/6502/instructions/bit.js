import { CycleType } from '..'

/**
 * BIT test
 *
 * A & M, N = M7, V = M6
 *
 * Affects Flags: N V Z
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Zero Page     BIT $44       $24  2   3
 * Absolute      BIT $4400     $2C  3   4
 */
export function* bit(mode, addr) {
  const a = this.acc
  const b = this.read(addr)
  this.zero = (a & b) === 0
  this.overflow = (b & 0x40) > 0
  this.negative = (b & 0x80) > 0
  yield CycleType.GET
}
