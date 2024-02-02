import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('jmp', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  mmu.data = [0x4c, 0x55, 0x97] // JMP $9755
  const g = cpu.run()
  for (let i = 0; i < 3; i++) g.next()
  expect(cpu.pc).toBe(0x9755)
})

test('jmp indirect', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  mmu.data = [0x6c, 0x55, 0x97] // JMP [$9755]
  mmu.data[0x9755] = 0x42
  mmu.data[0x9756] = 0x55
  const g = cpu.run()
  for (let i = 0; i < 5; i++) g.next()
  expect(cpu.pc).toBe(0x5542)
})

test('jmp indirect + hardware bug', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  mmu.data = [0x6c, 0xff, 0x97] // JMP [$97ff]
  mmu.data[0x97ff] = 0x42
  mmu.data[0x9700] = 0x55
  const g = cpu.run()
  for (let i = 0; i < 5; i++) g.next()
  expect(cpu.pc).toBe(0x5542)
})
