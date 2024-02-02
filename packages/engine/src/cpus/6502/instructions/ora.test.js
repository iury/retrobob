import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('ora imm', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  mmu.data = [0x9, 2] // ORA #$02
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.acc).toBe(2)
})

test('ora imm', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  mmu.data = [0x9, 1] // ORA #$01
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.acc).toBe(3)
})
