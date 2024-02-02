import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('eor imm', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  mmu.data = [0x49, 2] // EOR #$02
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.acc).toBe(0)
})

test('eor imm', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  mmu.data = [0x49, 1] // EOR #$01
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.acc).toBe(3)
})
