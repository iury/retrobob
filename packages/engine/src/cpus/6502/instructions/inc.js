import { CycleType } from '..'

/**
 * INCrement memory
 *
 * M,Z,N = M+1
 *
 * Affects Flags: N Z
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Zero Page     INC $44       $E6  2   5
 * Zero Page,X   INC $44,X     $F6  2   6
 * Absolute      INC $4400     $EE  3   6
 * Absolute,X    INC $4400,X   $FE  3   7
 */
export function* inc(mode, addr) {
  if (Array.isArray(addr) && !addr[1]) {
    this.read(addr[0])
    yield CycleType.GET
  }

  addr = Array.isArray(addr) ? addr[0] : addr
  let value = this.read(addr)
  yield CycleType.GET

  this.write(addr, value)
  yield CycleType.PUT

  if (++value > 255) value = 0
  this.write(addr, value)
  this.zero = value === 0
  this.negative = (value & 0x80) > 0
  yield CycleType.PUT
}
