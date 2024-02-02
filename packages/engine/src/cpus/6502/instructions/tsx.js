import { CycleType } from '..'

/**
 * Transfer Stack pointer to X
 *
 * X = SP
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       TSX           $BA  1   2
 */
export function* tsx() {
  this.x = this.sp
  this.zero = this.x === 0
  this.negative = (this.x & 0x80) > 0
  yield CycleType.GET
}
