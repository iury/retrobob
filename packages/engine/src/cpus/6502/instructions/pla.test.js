import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('plp', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.sp = 0xff
  cpu.acc = 0x42
  mmu.data = [0x48, 0x68] // PHA PLA
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.sp).toBe(0xfe)
  expect(mmu.data[0x1ff]).toBe(cpu.acc)

  cpu.acc = 0
  for (let i = 0; i < 4; i++) g.next()
  expect(cpu.sp).toBe(0xff)
  expect(cpu.acc).toBe(0x42)
})
