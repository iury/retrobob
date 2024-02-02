import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('cpy', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.y = 1
  mmu.data = [0xc0, 1] // CPY #$1
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.zero).toBeTruthy()
})
