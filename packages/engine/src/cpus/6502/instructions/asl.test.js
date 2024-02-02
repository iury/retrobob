import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('asl acc', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 1
  mmu.data = [0x0a] // ASL
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.acc).toBe(2)
})

test('asl zpg', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  mmu.data = [0x06, 0x02, 4] // ASL $02
  const g = cpu.run()
  for (let i = 0; i < 5; i++) g.next()
  expect(mmu.data[2]).toBe(8)
})

test('asl abs', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  mmu.data = [0x0e, 0x02, 0xff] // ASL $ff02
  mmu.data[0xff02] = 4
  const g = cpu.run()
  for (let i = 0; i < 6; i++) g.next()
  expect(mmu.data[0xff02]).toBe(8)
})
