import { AddressingMode, CycleType } from '..'

/**
 * No OPeration
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Implied       NOP           $EA  1   2
 */
export function* nop(mode, addr) {
  if (mode !== AddressingMode.IMP && mode !== AddressingMode.IMM) {
    this.read(Array.isArray(addr) ? addr[0] : addr)
  }
  yield CycleType.GET
}
