import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('cpx', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.x = 1
  mmu.data = [0xe0, 1] // CPX #$1
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.zero).toBeTruthy()
})
