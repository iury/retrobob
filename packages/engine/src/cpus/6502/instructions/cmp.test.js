import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('cmp', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 1
  mmu.data = [0xc9, 1] // CMP #$1
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.zero).toBeTruthy()
})
