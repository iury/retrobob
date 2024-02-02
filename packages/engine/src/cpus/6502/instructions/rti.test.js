import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('rti', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.sp = 0xff
  cpu.interruptDisabled = false
  cpu.zero = true
  mmu.data = [0x0] // BRK
  mmu.data[0xfffe] = 0x04
  mmu.data[0xffff] = 0xac
  const g = cpu.run()
  for (let i = 0; i < 7; i++) g.next()
  expect(cpu.pc).toBe(0x4ac)
  expect(mmu.data[0x1ff]).toBe(0)
  expect(mmu.data[0x1fe]).toBe(2)
  expect(mmu.data[0x1fd]).toBe((cpu.status | 0x10) & ~0x4)
  expect(cpu.interruptDisabled).toBeTruthy()

  mmu.data[0x4ac] = 0x40 // RTI
  cpu.zero = false
  for (let i = 0; i < 6; i++) g.next()
  expect(cpu.pc).toBe(2)
  expect(cpu.zero).toBeTruthy()
  expect(cpu.interruptDisabled).toBeFalsy()
})
