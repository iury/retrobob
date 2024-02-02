import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('bpl - negative:set', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.zero = true
  mmu.data = [0x10, 1] // BPL
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.pc).toBe(2)
})

test('bpl - negative:clear', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.zero = false
  mmu.data = [0x10, 1] // BPL
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(3)
})

test('bpl negative', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.negative = false
  mmu.data = [0x10, 0xff] // BPL
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(1)
})
