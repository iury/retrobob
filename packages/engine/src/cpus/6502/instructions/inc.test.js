import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('inc', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  mmu.data = [0xe6, 0x2, 0xff] // INC, $02
  const g = cpu.run()
  for (let i = 0; i < 5; i++) g.next()
  expect(mmu.data[0x2]).toBe(0)
})
