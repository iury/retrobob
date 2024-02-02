import { CycleType } from '..'

/**
 * STore Y register
 *
 * M = Y
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Zero Page     STY $44       $84  2   3
 * Zero Page,X   STY $44,Y     $94  2   4
 * Absolute      STY $4400     $8C  3   4
 */
export function* sty(mode, addr) {
  this.write(addr, this.y)
  yield CycleType.PUT
}
