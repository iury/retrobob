import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('sbc imm', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  cpu.carry = true
  mmu.data = [0xe9, 1] // SBC #$01
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.acc).toBe(1)
  expect(cpu.carry).toBeTruthy()
})
