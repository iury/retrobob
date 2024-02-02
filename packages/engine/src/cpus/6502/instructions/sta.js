import { CycleType } from '..'

/**
 * STore Accumulator
 *
 * M = A
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Zero Page     STA $44       $85  2   3
 * Zero Page,X   STA $44,X     $95  2   4
 * Absolute      STA $4400     $8D  3   4
 * Absolute,X    STA $4400,X   $9D  3   5
 * Absolute,Y    STA $4400,Y   $99  3   5
 * Indirect,X    STA ($44,X)   $81  2   6
 * Indirect,Y    STA ($44),Y   $91  2   6
 */
export function* sta(mode, addr) {
  if (Array.isArray(addr) && !addr[1]) {
    this.read(addr[0])
    yield CycleType.GET
  }

  this.write(Array.isArray(addr) ? addr[0] : addr, this.acc)
  yield CycleType.PUT
}
