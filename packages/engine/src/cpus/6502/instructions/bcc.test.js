import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('bcc - carry:set', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.carry = true
  mmu.data = [0x90, 1] // BCC
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.pc).toBe(2)
})

test('bcc - carry:clear', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.carry = false
  mmu.data = [0x90, 1] // BCC
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(3)
})

test('bcc negative', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.carry = false
  mmu.data = [0x90, 0xff] // BCC
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(1)
})
