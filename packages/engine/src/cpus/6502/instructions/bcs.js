import { CycleType } from '..'
import { fixRange16 } from '../../../utils'

/**
 * Branch if Carry Set
 *
 * MODE          SYNTAX        HEX LEN TIM
 * Relative      BCS LABEL     $B0  2   2+
 *
 * @example
 * + add 1 cycle if succeeds
 * + add 1 cycle if page boundary crossed
 */
export function* bcs(mode, offset) {
  if (this.carry) {
    this.read(this.pc)
    const crossed = this.checkPageCrossing(this.pc, offset)
    if (crossed) {
      yield CycleType.GET
      this.read((this.pc & 0xff00) | ((this.pc + offset) & 0xff))
    }
    this.pc = fixRange16(this.pc + offset)
    yield CycleType.GET
  }
}
