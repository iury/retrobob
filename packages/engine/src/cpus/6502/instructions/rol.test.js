import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('rol acc', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 0x80
  cpu.carry = true
  mmu.data = [0x2a] // ROL
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.acc).toBe(1)
  expect(cpu.carry).toBeTruthy()
})

test('rol zpg', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  mmu.data = [0x26, 0x02, 4] // ROL $02
  const g = cpu.run()
  for (let i = 0; i < 5; i++) g.next()
  expect(mmu.data[2]).toBe(8)
})

test('rol abs', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  mmu.data = [0x2e, 0x02, 0xff] // ROL $ff02
  mmu.data[0xff02] = 4
  const g = cpu.run()
  for (let i = 0; i < 6; i++) g.next()
  expect(mmu.data[0xff02]).toBe(8)
})
