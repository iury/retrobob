import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('clear instructions', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.carry = true
  cpu.interruptDisabled = true
  cpu.overflow = true
  mmu.data = [0x18, 0xd8, 0x58, 0xb8] // CLC CLD CLI CLV
  const g = cpu.run()
  for (let i = 0; i < 8; i++) g.next()
  expect(cpu.carry).toBeFalsy()
  expect(cpu.interruptDisabled).toBeFalsy()
  expect(cpu.overflow).toBeFalsy()
})

test('set instructions', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.carry = false
  cpu.interruptDisabled = false
  mmu.data = [0x38, 0xf8, 0x78] // SEC SED SEI
  const g = cpu.run()
  for (let i = 0; i < 6; i++) g.next()
  expect(cpu.carry).toBeTruthy()
  expect(cpu.interruptDisabled).toBeTruthy()
})
