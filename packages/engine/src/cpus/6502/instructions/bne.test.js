import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('bne - zero:set', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.zero = true
  mmu.data = [0xd0, 1] // BNE
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.pc).toBe(2)
})

test('bne - zero:clear', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.zero = false
  mmu.data = [0xd0, 1] // BNE
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(3)
})

test('bne negative', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.zero = false
  mmu.data = [0xd0, 0xff] // BNE
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(1)
})
