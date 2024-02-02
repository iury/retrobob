import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('dec', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  mmu.data = [0xc6, 0x2, 0x0] // DEC, $02
  const g = cpu.run()
  for (let i = 0; i < 5; i++) g.next()
  expect(mmu.data[0x2]).toBe(255)
})
