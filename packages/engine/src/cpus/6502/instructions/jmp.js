import { AddressingMode, CycleType } from '..'

/**
 * JuMP
 *
 * @example
 * MODE          SYNTAX        HEX LEN TIM
 * Absolute      JMP $5597     $4C  3   3
 * Indirect      JMP ($5597)   $6C  3   5
 */
export function* jmp(mode) {
  if (mode === AddressingMode.ABS) {
    const pcl = this.fetch()
    yield CycleType.GET
    this.pc = (this.fetch() << 8) | pcl
    yield CycleType.GET
  } else {
    let addr = this.fetch()
    yield CycleType.GET
    addr = (this.fetch() << 8) | addr
    yield CycleType.GET
    const pcl = this.read(addr)
    yield CycleType.GET
    if ((addr & 0xff) === 0xff) addr = addr & 0xff00
    else addr++
    this.pc = (this.read(addr) << 8) | pcl
    yield CycleType.GET
  }
}
