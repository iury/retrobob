import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('dey', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.y = 0
  mmu.data = [0x88] // DEY
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.y).toBe(255)
})
