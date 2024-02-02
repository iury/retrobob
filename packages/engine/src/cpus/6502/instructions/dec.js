import { CycleType } from '..'

/**
 * DECrement memory
 *
 * M,Z,N = M-1
 *
 * Affects Flags: N Z
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Zero Page     DEC $44       $C6  2   5
 * Zero Page,X   DEC $44,X     $D6  2   6
 * Absolute      DEC $4400     $CE  3   6
 * Absolute,X    DEC $4400,X   $DE  3   7
 */
export function* dec(mode, addr) {
  if (Array.isArray(addr) && !addr[1]) {
    this.read(addr[0])
    yield CycleType.GET
  }

  addr = Array.isArray(addr) ? addr[0] : addr
  let value = this.read(addr)
  yield CycleType.GET

  this.write(addr, value)
  yield CycleType.PUT

  if (--value < 0) value = 0xff
  this.write(addr, value)
  this.zero = value === 0
  this.negative = (value & 0x80) > 0
  yield CycleType.PUT
}
