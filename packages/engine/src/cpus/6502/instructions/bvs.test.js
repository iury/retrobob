import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('bvs - overflow:clear', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.zero = true
  mmu.data = [0x70, 1] // BVS
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.pc).toBe(2)
})

test('bvs - overflow:set', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.overflow = true
  mmu.data = [0x70, 1] // BVS
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(3)
})

test('bvs negative', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.overflow = true
  mmu.data = [0x70, 0xff] // BVS
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(1)
})
