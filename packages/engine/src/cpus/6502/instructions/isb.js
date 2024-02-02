import { CycleType } from '..'
import { uint8sub } from '../../../utils'

/// extra opcode isb
export function* isb(mode, addr) {
  if (Array.isArray(addr) && !addr[1]) {
    this.read(addr[0])
    yield CycleType.GET
  }

  addr = Array.isArray(addr) ? addr[0] : addr
  let value = this.read(addr)
  yield CycleType.GET

  this.write(addr, value)
  yield CycleType.PUT

  if (++value > 255) value = 0
  this.write(addr, value)

  const a = this.acc
  const b = value
  const [result, carry] = uint8sub(a, b, this.carry ? 0 : 1)
  this.acc = result
  this.zero = result === 0
  this.negative = (result & 0x80) > 0
  this.carry = !carry
  this.overflow = ((a ^ this.acc) & ((255 - b) ^ this.acc) & 0x80) > 0
  yield CycleType.PUT
}
