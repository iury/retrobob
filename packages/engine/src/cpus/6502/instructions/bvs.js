import { CycleType } from '..'
import { fixRange16 } from '../../../utils'

/**
 * Branch if oVerflow Set
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Relative      BVS LABEL     $70  2   2+
 *
 * + add 1 cycle if succeeds
 * + add 1 cycle if page boundary crossed
 */
export function* bvs(mode, offset) {
  if (this.overflow) {
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
