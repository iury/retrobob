import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('inx', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.x = 255
  mmu.data = [0xe8] // INX
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.x).toBe(0)
})
