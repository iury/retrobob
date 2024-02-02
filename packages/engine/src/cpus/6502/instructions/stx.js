import { CycleType } from '..'

/**
 * STore X register
 *
 * M = X
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Zero Page     STX $44       $86  2   3
 * Zero Page,Y   STX $44,Y     $96  2   4
 * Absolute      STX $4400     $8E  3   4
 */
export function* stx(mode, addr) {
  this.write(addr, this.x)
  yield CycleType.PUT
}
