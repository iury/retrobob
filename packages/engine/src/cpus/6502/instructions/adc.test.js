import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('adc imm', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  mmu.data = [0x69, 3] // ADC #$03
  const g = cpu.run()
  for (let i = 0; i < 2; i++) g.next()
  expect(cpu.acc).toBe(5)
})

test('adc abs', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  mmu.data = [0x6d, 0x03, 0x0, 1] // ADC $03
  const g = cpu.run()
  for (let i = 0; i < 4; i++) g.next()
  expect(cpu.acc).toBe(3)
})

test('adc abx', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  cpu.x = 2
  mmu.data = [0x7d, 0x01, 0x0, 1] // ADC X+$01
  const g = cpu.run()
  for (let i = 0; i < 4; i++) g.next()
  expect(cpu.acc).toBe(3)
})

test('adc abx + page crossing', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  cpu.x = 1
  mmu.data = [0x7d, 0xff, 0x0] // ADC X+$FF=$100
  mmu.data[0x100] = 3
  const g = cpu.run()
  for (let i = 0; i < 5; i++) g.next()
  expect(cpu.acc).toBe(5)
})

test('adc aby', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  cpu.y = 2
  mmu.data = [0x79, 0x01, 0x0, 1] // ADC Y+$01
  const g = cpu.run()
  for (let i = 0; i < 4; i++) g.next()
  expect(cpu.acc).toBe(3)
})

test('adc zpg', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  mmu.data = [0x65, 0x02, 1] // ADC $02
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.acc).toBe(3)
})

test('adc zpx', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  cpu.x = 1
  mmu.data = [0x75, 0x02, 0, 1] // ADC X+$02
  const g = cpu.run()
  for (let i = 0; i < 4; i++) g.next()
  expect(cpu.acc).toBe(3)
})

test('adc idx', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 5
  cpu.x = 1
  mmu.data = [0x61, 0xff] // ADC [[X+#$FF]]=$FF02
  mmu.data[0x4] = 2
  mmu.data[0x5] = 0xff
  mmu.data[0xff02] = 3
  const g = cpu.run()
  for (let i = 0; i < 6; i++) g.next()
  expect(cpu.acc).toBe(5)
})

test('adc idy', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  cpu.y = 1
  mmu.data = [0x71, 0xfe] // ADC Y+[[#$FF]=$FF02]
  mmu.data[0xfe] = 2
  mmu.data[0xff] = 0xff
  mmu.data[0xff03] = 3
  const g = cpu.run()
  for (let i = 0; i < 5; i++) g.next()
  expect(cpu.acc).toBe(5)
})

test('adc idy + page crossing', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.acc = 2
  cpu.y = 1
  mmu.data = [0x71, 0xfe] // ADC Y+[[#$FF]=$FF02]
  mmu.data[0xfe] = 0xff
  mmu.data[0xff] = 0xef
  mmu.data[0xf000] = 3
  const g = cpu.run()
  for (let i = 0; i < 6; i++) g.next()
  expect(cpu.acc).toBe(5)
})
