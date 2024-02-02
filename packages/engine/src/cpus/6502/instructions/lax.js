import { CycleType } from '..'

/// extra opcode lax = lda + ldx
export function* lax(mode, addr) {
  this.acc = this.read(Array.isArray(addr) ? addr[0] : addr)
  this.x = this.acc
  this.zero = this.x === 0
  this.negative = (this.x & 0x80) > 0
  yield CycleType.GET
}
