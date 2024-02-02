import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('and imm', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  mmu.data = [0x29, 2] // AND #$02
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.acc).toBe(2)
})

test('and imm', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  mmu.data = [0x29, 1] // AND #$01
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.acc).toBe(0)
})
