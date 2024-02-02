import { test, expect } from 'vitest'
import { fixRange8, fixRange16, uint8add, uint8sub } from './utils'

test('uint8add', () => {
  expect(uint8add(1, 2)).toStrictEqual([3, false])
  expect(uint8add(254, 1)).toStrictEqual([255, false])
  expect(uint8add(255, 1)).toStrictEqual([0, true])
  expect(uint8add(254, 1, [1, false])).toStrictEqual([0, true])
  expect(uint8add(1, [1, true])).toStrictEqual([2, true])
})

test('uint8sub', () => {
  expect(uint8sub(2, 1)).toStrictEqual([1, false])
  expect(uint8sub(0, 1)).toStrictEqual([255, true])
  expect(uint8sub(0, 1, 1)).toStrictEqual([254, true])
  expect(uint8sub(255, 255)).toStrictEqual([0, false])
  expect(uint8sub(255, 255, 1)).toStrictEqual([255, true])
})

test('fixRange8', () => {
  expect(fixRange8(0)).toBe(0)
  expect(fixRange8(1)).toBe(1)
  expect(fixRange8(0xff)).toBe(0xff)
  expect(fixRange8(0x100)).toBe(0)
  expect(fixRange8(0x2ff)).toBe(0xff)
  expect(fixRange8(-1)).toBe(0xff)
  expect(fixRange8(-2)).toBe(0xfe)
})

test('fixRange16', () => {
  expect(fixRange16(0)).toBe(0)
  expect(fixRange16(1)).toBe(1)
  expect(fixRange16(0xffff)).toBe(0xffff)
  expect(fixRange16(0x10000)).toBe(0)
  expect(fixRange16(0x2ffff)).toBe(0xffff)
  expect(fixRange16(-1)).toBe(0xffff)
  expect(fixRange16(-2)).toBe(0xfffe)
})
