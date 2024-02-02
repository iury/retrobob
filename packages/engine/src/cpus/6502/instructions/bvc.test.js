import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('bvc - overflow:set', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.zero = true
  mmu.data = [0x50, 1] // BVC
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.pc).toBe(2)
})

test('bvc - overflow:clear', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.overflow = false
  mmu.data = [0x50, 1] // BVC
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(3)
})

test('bvc negative', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.overflow = false
  mmu.data = [0x50, 0xff] // BVC
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(1)
})
