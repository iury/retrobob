import { CycleType } from '..'

/// extra opcode dcp
export function* dcp(mode, addr) {
  if (Array.isArray(addr) && !addr[1]) {
    this.read(addr[0])
    yield CycleType.GET
  }

  addr = Array.isArray(addr) ? addr[0] : addr
  let value = this.read(addr)
  yield CycleType.GET

  this.write(addr, value)
  yield CycleType.PUT

  if (--value < 0) value = 0xff
  this.write(addr, value)

  this.carry = this.acc >= value
  this.zero = this.acc === value
  let v = this.acc - value
  if (v < 0) v = 256 + v
  this.negative = (v & 0x80) > 0
  yield CycleType.PUT
}
