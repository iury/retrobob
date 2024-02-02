import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('lsr acc', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 255
  mmu.data = [0x4a] // LSR
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.acc).toBe(127)
  expect(cpu.carry).toBeTruthy()
})

test('lsr zpg', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  mmu.data = [0x46, 0x02, 4] // LSR $02
  const g = cpu.run()
  for (let i = 0; i < 5; i++) g.next()
  expect(mmu.data[2]).toBe(2)
})

test('lsr abs', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  mmu.data = [0x4e, 0x02, 0xff] // LSR $ff02
  mmu.data[0xff02] = 4
  const g = cpu.run()
  for (let i = 0; i < 6; i++) g.next()
  expect(mmu.data[0xff02]).toBe(2)
})
