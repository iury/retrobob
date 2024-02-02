import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('iny', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.y = 255
  mmu.data = [0xc8] // INY
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.y).toBe(0)
})
