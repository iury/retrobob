import { test, expect } from 'vitest'
import { BufferMapper } from '../../../buffer_mapper'
import { CPU } from '..'

test('jsr', () => {
  const mmu = new BufferMapper()
  const cpu = new CPU(mmu)
  cpu.sp = 0xff
  mmu.data = [0x20, 0xac, 0x4] // JSR $04ac
  const g = cpu.run()
  for (let i = 0; i < 6; i++) g.next()
  expect(cpu.pc).toBe(0x4ac)
  expect(mmu.data[0x1ff]).toBe(0)
  expect(mmu.data[0x1fe]).toBe(2)
})
