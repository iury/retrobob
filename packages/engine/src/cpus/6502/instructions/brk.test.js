import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('brk', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.sp = 0xff
  cpu.interruptDisabled = false
  mmu.data = [0x0] // BRK
  mmu.data[0xfffe] = 0x04
  mmu.data[0xffff] = 0xac
  const g = cpu.run()
  for (let i = 0; i < 7; i++) g.next()
  expect(cpu.pc).toBe(0x4ac)
  expect(mmu.data[0x1ff]).toBe(0)
  expect(mmu.data[0x1fe]).toBe(2)
  expect(mmu.data[0x1fd]).toBe((cpu.status | 0x10) & ~0x4)
})

test('brk hijacked', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.sp = 0xff
  cpu.interruptDisabled = false
  mmu.data = [0x0] // BRK
  mmu.data[0xfffa] = 0x04
  mmu.data[0xfffb] = 0xac
  const g = cpu.run()
  for (let i = 0; i < 7; i++) {
    if (i === 1) cpu.nmiRequested = true
    g.next()
  }
  expect(cpu.pc).toBe(0x4ac)
  expect(mmu.data[0x1ff]).toBe(0)
  expect(mmu.data[0x1fe]).toBe(2)
  expect(mmu.data[0x1fd]).toBe((cpu.status | 0x10) & ~0x4)
})
