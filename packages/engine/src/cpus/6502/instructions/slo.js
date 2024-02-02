import { CycleType } from '..'

/// extra opcode slo
export function* slo(mode, addr) {
  if (Array.isArray(addr) && !addr[1]) {
    this.read(addr[0])
    yield CycleType.GET
  }

  addr = Array.isArray(addr) ? addr[0] : addr
  let b = this.read(addr)
  yield CycleType.GET

  this.write(addr, b)
  yield CycleType.PUT

  this.carry = (b & 0x80) > 0
  b = (b << 1) % 256
  this.write(addr, b)

  this.acc |= b
  this.zero = this.acc === 0
  this.negative = (this.acc & 0x80) > 0
  yield CycleType.PUT
}
