import { CycleType } from '..'
import { uint8add } from '../../../utils'

/// extra opcode rra
export function* rra(mode, addr) {
  if (Array.isArray(addr) && !addr[1]) {
    this.read(addr[0])
    yield CycleType.GET
  }

  addr = Array.isArray(addr) ? addr[0] : addr
  let b = this.read(addr)
  yield CycleType.GET

  this.write(addr, b)
  yield CycleType.PUT

  const c = this.carry ? 0x80 : 0
  this.carry = (b & 0x1) > 0
  b = (b >>> 1) | c
  this.write(addr, b)

  const a = this.acc
  const [result, carry] = uint8add(a, b, this.carry ? 1 : 0)
  this.acc = result
  this.zero = result === 0
  this.negative = (result & 0x80) > 0
  this.carry = carry
  this.overflow = ((a ^ result) & (b ^ result) & 0x80) > 0
  yield CycleType.PUT
}
