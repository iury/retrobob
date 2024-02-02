import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('ror acc', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 254
  cpu.carry = true
  mmu.data = [0x6a] // ROR
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.acc).toBe(255)
  expect(cpu.carry).toBeFalsy()
})

test('ror zpg', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  mmu.data = [0x66, 0x02, 4] // ROR $02
  const g = cpu.run()
  for (let i = 0; i < 5; i++) g.next()
  expect(mmu.data[2]).toBe(2)
})

test('ror abs', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  mmu.data = [0x6e, 0x02, 0xff] // ROR $ff02
  mmu.data[0xff02] = 4
  const g = cpu.run()
  for (let i = 0; i < 6; i++) g.next()
  expect(mmu.data[0xff02]).toBe(2)
})
