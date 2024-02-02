import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('plp', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.sp = 0xff
  cpu.zero = true
  mmu.data = [0x08, 0x28] // PHP PLP
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.sp).toBe(0xfe)
  expect(mmu.data[0x1ff]).toBe(cpu.status | 0x10)

  cpu.zero = false
  for (let i = 0; i < 4; i++) g.next()
  expect(cpu.sp).toBe(0xff)
  expect(cpu.breakCommand).toBeFalsy()
  expect(cpu.zero).toBeTruthy()
})
