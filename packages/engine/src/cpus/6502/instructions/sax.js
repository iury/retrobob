import { CycleType } from '..'

/// extra opcode sax = st(a&x)
export function* sax(mode, addr) {
  this.write(addr, this.acc & this.x)
  yield CycleType.PUT
}
