import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('bit - zpg', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  mmu.data = [0x24, 0x44] // BIT $44
  mmu.data[0x44] = 2
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.zero).toBe(false)
})

test('bit - abs', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  mmu.data = [0x24, 0x00, 0x44] // BIT $4400
  mmu.data[0x4400] = 1
  const g = cpu.run()
  for (let i = 0; i < 4; i++) g.next()
  expect(cpu.zero).toBe(true)
})
