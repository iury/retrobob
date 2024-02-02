import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('bmi - negative:clear', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.negative = false
  mmu.data = [0x30, 1] // BMI
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.pc).toBe(2)
})

test('bmi - negative:set', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.negative = true
  mmu.data = [0x30, 1] // BMI
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(3)
})

test('bmi negative', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.negative = true
  mmu.data = [0x30, 0xff] // BMI
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(1)
})
