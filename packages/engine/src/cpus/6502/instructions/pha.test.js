import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('pha', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.sp = 0xff
  cpu.acc = 0x42
  mmu.data = [0x48] // PHA
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.sp).toBe(0xfe)
  expect(mmu.data[0x1ff]).toBe(cpu.acc)
})
