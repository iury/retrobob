import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('dex', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.x = 0
  mmu.data = [0xca] // DEX
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.x).toBe(255)
})
