import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('irq', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.sp = 0xff
  cpu.interruptDisabled = false
  cpu.irqRequested = true
  mmu.data[0xfffe] = 0xac
  mmu.data[0xffff] = 0x04
  const g = cpu.run()
  for (let i = 0; i < 7; i++) g.next()
  expect(cpu.pc).toBe(0x4ac)
  expect(mmu.data[0x1ff]).toBe(0)
  expect(mmu.data[0x1fe]).toBe(0)
  expect(mmu.data[0x1fd]).toBe(cpu.status & ~0x14)
})

test('nmi', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.sp = 0xff
  cpu.nmiRequested = true
  cpu.interruptDisabled = false
  mmu.data[0xfffa] = 0xac
  mmu.data[0xfffb] = 0x04
  const g = cpu.run()
  for (let i = 0; i < 7; i++) g.next()
  expect(cpu.pc).toBe(0x4ac)
  expect(mmu.data[0x1ff]).toBe(0)
  expect(mmu.data[0x1fe]).toBe(0)
  expect(mmu.data[0x1fd]).toBe(cpu.status & ~0x14)
})

test('rst', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.sp = 0xff
  cpu.interruptDisabled = false
  cpu.rstRequested = true
  mmu.data[0x1ff] = 0xff
  mmu.data[0x1fe] = 0xff
  mmu.data[0xfffc] = 0xac
  mmu.data[0xfffd] = 0x04
  const g = cpu.run()
  for (let i = 0; i < 7; i++) g.next()
  expect(cpu.pc).toBe(0x4ac)
  expect(mmu.data[0x1ff]).toBe(0xff)
  expect(mmu.data[0x1fe]).toBe(0xff)
  expect(cpu.interruptDisabled).toBe(true)
})
