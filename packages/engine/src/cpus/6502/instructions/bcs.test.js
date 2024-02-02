import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('bcs - carry:set', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.carry = true
  mmu.data = [0xb0, 1] // BCS
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.pc).toBe(2)
})

test('bcs - carry:clear', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.carry = false
  mmu.data = [0xb0, 1] // BCS
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(3)
})

test('bcs negative', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.carry = true
  mmu.data = [0xb0, 0xff] // BCS
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(1)
})
